defmodule Worker do
  require Logger
  use GenServer, restart: :temporary

  defmodule State do
    @enforce_keys [:symbol, :status, :report_to]
    defstruct symbol: nil,
              status: :ready,
              report_to: nil,
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
    updated_history = [{module_name, fun_name} | history]
    updated_state = %{state | step_context: updated_context, history: updated_history}

    {:noreply, updated_state}
  end

  @impl true
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(reason, %{step_context: context} = _state) do
    reason |> IO.inspect(label: "#{__MODULE__} 64")
    context |> IO.inspect(label: "#{__MODULE__} 65")
    :normal
  end

  def run_step(%{worker_pid: pid, module_name: module, step_name: step}) do
    GenServer.cast(pid, {:run_step, module, step})
  end

  def current_state(worker_pid) do
    GenServer.call(worker_pid, {:current_state})
  end
end
