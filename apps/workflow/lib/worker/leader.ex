defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              workers: []
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}-#{symbol}")
  end

  @impl true
  def init(symbol) do
    {:ok, %State{symbol: symbol}, {:continue, :start_worker}}
  end

  @impl true
  def handle_continue(:start_worker, %{symbol: symbol} = state) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    workers = for _i <- 1..settings.n_workers, do: start_new_worker(worker_state)

    {:noreply, %{state | settings: settings, workers: workers}}
  end

  defp fetch_symbol_settings(_symbol) do
    %{
      n_workers: 1
    }
  end

  defp fresh_worker_state(_settings) do
    struct(Worker.State)
  end

  def start_new_worker(%Worker.State{} = state) do
    DynamicSupervisor.start_child(
      :"DynamicWorkerSupervisor-#{state.symbol}",
      {Worker, state}
    )
  end
end
