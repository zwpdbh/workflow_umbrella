defmodule Worker do
  require Logger
  use GenServer, restart: :temporary

  defmodule State do
    @enforce_keys [:symbol, :status, :report_to]
    defstruct symbol: nil,
              status: :ready,
              report_to: nil,
              current_step: nil,
              workload_history: [],
              context: %{}
  end

  @doc """
  This function is needed because we create worker dynamically via "DynamicSupervisor.start_child"
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
    # The place to fully initialize worker before doing task

    # # Notice leader that I am ready
    GenServer.cast(leader, {:worker_is_ready, self()})

    # GenServer.call(leader, %{msg: :ready})
    # send(leader, {who: self(), msg: :ready})

    {:noreply, state}
  end

  # # Process workflow
  # def handle_info(
  #       %{workflow_id: _workflow_id, workflow_parameters: _workflow_parameters},
  #       %State{context: _context} = state
  #     ) do
  #   # fetch workflow definition
  #   # execute workflow using workflow_parameters + context
  #   {:noreply, state}
  # end

  @impl true
  def handle_cast(
        {:process_workflow, %{steps: workflow_steps, id: workflow_id} = workflow},
        state
      ) do
    Logger.info(
      "Assigned workflow #{workflow_id}, there are #{workflow_steps |> length} steps to do"
    )

    # We process workflow by keep send ourself messages.
    # https://hexdocs.pm/elixir/GenServer.html#module-receiving-regular-messages

    send(self(), {:run_workflow, workflow})
    {:noreply, state}
  end

  # Callback for runing workflow which its steps is empty.
  # We should stop the worker and let leader restart it.
  @impl true
  def handle_info(
        {:run_workflow, %{steps: [], id: workflow_id}},
        %State{report_to: leader} = state
      ) do
    Logger.info("There is no more steps to execute in workflow #{workflow_id}, exit...")
    GenServer.call(leader, {:workflow_is_finished})

    {:stop, :normal, state}
  end

  # Callback for running workflow
  # It runs workflow by running a step from the workflow recursively.
  @impl true
  def handle_info(
        {:run_workflow, [step | rest]},
        %State{workload_history: workload_history} = state
      ) do
    Logger.info("Execute step: #{{inspect(step)}}")
    Logger.info("Update state")

    updated_history = [step | workload_history]
    updated_state = Map.put(state, :workload_history, updated_history)

    send(self(), {:run_workflow, [rest]})
    {:noreply, updated_state}
  end
end
