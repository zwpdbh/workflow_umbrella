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
    report_ready(leader)
    # GenServer.call(leader, %{msg: :ready})
    # send(leader, {who: self(), msg: :ready})

    {:noreply, state}
  end

  defp report_ready(leader) do
    GenServer.cast(leader, %{msg: :ready, from: self()})
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
  def handle_cast(%{execute: workflows}, state) do
    Logger.info("Assigned workflow, there are #{workflows |> length} steps to do")

    {:noreply, state}
  end

  def process_workflow(%{workflow_id: _workflow_id, workflow_parameters: _workflow_parameters}) do
    # fetch workflow definition
    # execute workflow's steps one after another in the GenServer process
    # how ? check Plug for insight
  end
end
