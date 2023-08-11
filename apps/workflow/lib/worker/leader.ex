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
    {:ok, %State{symbol: symbol}, {:continue, :start_workers}}
  end

  @impl true
  def handle_continue(:start_workers, %{symbol: symbol} = state) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    workers = for _i <- 1..settings.n_workers, do: start_new_worker(worker_state)

    {:noreply, %{state | settings: settings, workers: workers}}
  end

  # @impl true
  # def handle_info({who: some_worker_pid, msg: :ready}, state) do
  #   Logger.info("worker #{some_worker_pid} is ready")

  #   # Assign it with workflow to execute
  #   send(some_worker_pid, {msg: :execute, payload: %{}})

  #   {:noreply, state}
  # end

  @impl true
  def handle_cast(%{msg: :ready, from: some_worker}, state) do
    Logger.info("worker #{inspect(some_worker)} is ready")
    # Assign it with workflow to execute

    GenServer.cast(some_worker, %{execute: []})
    {:noreply, state}
  end

  # @impl true
  # def handle_call(%{msg: :ready}, some_worker, state) do
  #   Logger.info("worker #{some_worker} is ready")
  #   # Assign it with workflow to execute

  #   {:reply, %{workflow: []}, state}
  # end

  defp fetch_symbol_settings(symbol) do
    %{
      symbol: symbol,
      n_workers: 1,
      report_to: self()
    }
  end

  defp fresh_worker_state(settings) do
    struct(Worker.State, settings)
  end

  def start_new_worker(%Worker.State{symbol: symbol} = state) do
    symbol |> IO.inspect(label: "#{__MODULE__} 41")

    DynamicSupervisor.start_child(
      :"DynamicWorkerSupervisor-#{symbol}",
      {Worker, state}
    )
  end
end
