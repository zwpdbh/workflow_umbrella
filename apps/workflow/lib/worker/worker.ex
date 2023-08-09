defmodule Worker do
  require Logger
  use GenServer, restart: :temporary

  defmodule State do
    @enforce_keys [:symbol, :status, :current_step, :workload_history, :context]
    defstruct symbol: nil,
              status: :ready,
              current_step: nil,
              workload_history: [],
              context: %{}
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{symbol: symbol} = _state) do
    Logger.info("Initializing new worker for #{symbol}")
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

  def process_workflow(%{workflow_id: _workflow_id, workflow_parameters: _workflow_parameters}) do
    # fetch workflow definition
    # execute workflow's steps one after another in the GenServer process
    # how ? check Plug for insight
  end
end
