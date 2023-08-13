defmodule SymbolSupervisor do
  use Supervisor
  require Logger

  def start_link(symbol) do
    Supervisor.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    Logger.info("Starting new supervision tree for scenario #{symbol}")

    Supervisor.init(
      [
        {
          DynamicSupervisor,
          strategy: :one_for_one, name: :"DynamicWorkerSupervisor_#{symbol}"
        },
        {Worker.Leader, symbol}
      ],
      strategy: :one_for_all
    )
  end
end
