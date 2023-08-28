defmodule Worker do
  require Logger
  use GenServer, restart: :temporary

  defmodule State do
    @enforce_keys [:symbol, :status, :report_to]
    defstruct symbol: nil,
              name: nil,
              status: :ready,
              report_to: nil,
              # history is a list of tuples {which_function, which_module, error_message}
              history: [],
              step_context: %{}
  end

  @doc """
  This function is needed because we create worker dynamically via "DynamicSupervisor.start_child"
  Notice: we shall never name a process if it is created dynamically.
  """
  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(%State{symbol: symbol} = state) do
    Logger.info("Initializing new worker for #{symbol}")

    {:ok, state, {:continue, :ask_task}}
  end

  @impl true
  def handle_continue(:ask_task, %State{report_to: leader} = state) do
    # (TODO)The place to fully initialize worker before doing task
    # Notice leader that I am ready
    GenServer.cast(leader, {:worker_is_ready, self()})

    {:noreply, state}
  end

  # The worker is not aware of the concept of workflow.
  # The worker just execute a function assigned to it using context it current holds
  @impl true
  def handle_cast(
        {:run_step, module_name, fun_name},
        %State{step_context: context, history: history} = state
      ) do
    new_context =
      apply(
        String.to_existing_atom("Elixir.#{module_name}"),
        String.to_existing_atom("#{fun_name}"),
        [context]
      )

    updated_context = Map.merge(context, new_context)
    updated_history = [{module_name, fun_name, nil} | history]
    updated_state = %{state | step_context: updated_context, history: updated_history}

    {:noreply, updated_state}
  end

  @impl true
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(
        {err,
         [{which_module, which_function, _arity, [file: _filename, line: _line_num]} | _rest] =
           _stacktrace} = _reason,
        %{symbol: symbol, history: history} = state
      ) do
    worker_leader_pid = Process.whereis(Worker.Leader.get_leader_from_symbol(symbol))

    case err do
      {:badmatch, {:err, step_output}} ->
        Logger.warn("step error in #{which_module}.#{which_function}: #{step_output}")

        # Don't forget to update failed step into history

        send(
          worker_leader_pid,
          {:worker_step_error,
           %{
             which_module: which_module,
             which_function: which_function,
             step_output: step_output,
             worker_state: %{
               state
               | history: [{which_module, which_function, step_output} | history]
             }
           }}
        )

      unknow_error ->
        Logger.error("unknow error #{IO.inspect(unknow_error)}")
    end

    :normal
  end

  def run_step(%{worker_pid: pid, module_name: module, step_name: step}) do
    GenServer.cast(pid, {:run_step, module, step})
  end

  def worker_state(worker_pid) do
    GenServer.call(worker_pid, {:current_state})
  end
end
