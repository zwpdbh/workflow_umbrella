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

  # Callback for execute a step and update worker's internal state
  # The worker is not aware of the concept of workflow.
  # The worker just execute a function assigned to it using context it current holds
  @impl true
  def handle_cast(
        {:run_step, module_name, fun_name},
        %State{step_context: context, history: history} = state
      ) do
    # We need to update to leader that we are running some step because the internal state will be blocked in current process.
    # If some step takes a lot of time to execute, we need to update let leader know how this.

    # (TODO) maybe we just need to keep a "in_progress" table in leader ?
    # {:ok, worker_leader_pid} = get_leader_pid_from_symbol(symbol)

    # send(
    #   worker_leader_pid,
    #   {:worker_in_progress, %{state | history: {}}}
    # )

    # if the execution of step has no error, we update context and history
    # if there is error, the terminate callback will handle
    new_context = run_and_update_context(context, module_name, fun_name)

    updated_context = Map.merge(context, new_context)
    updated_history = [{module_name, fun_name, "succeed", nil} | history]
    updated_state = %{state | step_context: updated_context, history: updated_history}

    {:noreply, updated_state}
  end

  # Callback almost same from above except this will update its step execution result to Leader
  @impl true
  def handle_cast(
        {:run_step,
         %{
           worker_name: worker_name,
           which_module: which_module,
           which_function: which_function,
           step_index: step_index,
           step_id: _step_id
         }},
        %State{step_context: context, history: history, symbol: symbol} = state
      ) do
    new_context = run_and_update_context(context, which_module, which_function)
    updated_context = Map.merge(context, new_context)
    updated_history = [{which_module, which_function, "succeed", nil} | history]
    updated_state = %{state | step_context: updated_context, history: updated_history}

    {:ok, worker_leader_pid} = Worker.Leader.get_leader_pid_from_symbol(symbol)

    send(
      worker_leader_pid,
      {:worker_step_finished,
       %{
         # We pass worker's id to let Leader verify in its worker_registry
         worker_pid: self(),
         worker_name: worker_name,
         step_index: step_index,
         step_status: "succeed"
       }}
    )

    {:noreply, updated_state}
  end

  defp run_and_update_context(context, module_name, fun_name) do
    apply(
      String.to_existing_atom("Elixir.#{module_name}"),
      String.to_existing_atom("#{fun_name}"),
      [context]
    )
  end

  @impl true
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:add_new_context, new_context}, _from, %{step_context: step_context} = state) do
    updated_step_context = Map.merge(step_context, new_context)
    {:reply, updated_step_context, %{state | step_context: updated_step_context}}
  end

  @impl true
  def terminate(
        {err,
         [{which_module, which_function, _arity, [file: _filename, line: _line_num]} | _rest] =
           _stacktrace} = _reason,
        %{symbol: symbol, history: history} = state
      ) do
    "??????" |> IO.inspect(label: "#{__MODULE__} 131")
    {:ok, worker_leader_pid} = Worker.Leader.get_leader_pid_from_symbol(symbol)

    case err do
      {:badmatch, {:err, step_output}} ->
        Logger.warn("step error in #{which_module}.#{which_function}: #{step_output}")

        # Don't forget to update failed step into history

        notic_leader_worker_error(%{
          leader: worker_leader_pid,
          which_module: which_module,
          which_function: which_function,
          step_output: step_output,
          worker_state: state,
          history: history
        })

      unknow_error ->
        Logger.debug("unknow error #{inspect(unknow_error)}")

        notic_leader_worker_error(%{
          leader: worker_leader_pid,
          which_module: which_module,
          which_function: which_function,
          step_output: unknow_error,
          worker_state: state,
          history: history
        })
    end

    :normal
  end

  defp notic_leader_worker_error(%{
         leader: leader_pid,
         which_module: which_module,
         which_function: which_function,
         step_output: stepoutput,
         worker_state: state,
         history: current_history
       }) do
    send(
      leader_pid,
      {:worker_step_error,
       %{
         which_module: which_module,
         which_function: which_function,
         step_output: "#{inspect(stepoutput)}",
         worker_pid: self(),
         worker_state: %{
           state
           | history: [
               {which_module, which_function, "failed", "#{inspect(stepoutput)}"}
               | current_history
             ]
         }
       }}
    )
  end

  # @impl true
  # def handle_cast

  def run_step(%{worker_pid: pid, module_name: module, step_name: step}) do
    GenServer.cast(pid, {:run_step, module, step})
  end

  def run_step_with_id(%{
        worker_pid: worker_pid,
        worker_name: worker_name,
        which_module: which_module,
        which_function: which_function,
        step_index: step_index,
        step_id: step_id
      }) do
    GenServer.cast(
      worker_pid,
      {:run_step,
       %{
         worker_name: worker_name,
         which_module: which_module,
         which_function: which_function,
         step_index: step_index,
         step_id: step_id
       }}
    )
  end

  def worker_state(worker_pid) do
    GenServer.call(worker_pid, {:current_state})
  end

  # Helper function to add extra context
  def add_worker_context(worker_pid, new_context) when is_map(new_context) do
    GenServer.call(worker_pid, {:add_new_context, new_context})
  end
end
