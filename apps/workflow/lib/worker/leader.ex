defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              workers: nil
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    {:ok, %State{symbol: symbol, workers: %{}}, {:continue, :init_workers}}
  end

  @impl true
  def handle_continue(:init_workers, %{symbol: symbol, workers: workers} = state) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    # We shall maintain our own worker registering logic
    # Do not name process create dynamically (do not naming worker process)
    updated_workers =
      1..settings.n_workers
      |> Enum.to_list()
      |> Enum.reduce(
        workers,
        fn index, acc ->
          {:ok, worker_pid} =
            Map.merge(worker_state, %{name: "worker#{index}"}) |> start_new_worker()

          Map.put(
            acc,
            "worker#{index}",
            worker_pid
          )
        end
      )

    {:noreply, %{state | settings: settings, workers: updated_workers}}
    # {:noreply, %{state | settings: settings}}
  end

  defp fetch_symbol_settings(symbol) do
    # Load settings for some symbol (scenario)
    # (TODO) how to handle settings are failed to load for some scenarios just created.
    %{
      symbol: symbol,
      n_workers: 1,
      report_to: self()
    }
  end

  defp fresh_worker_state(settings) do
    # For now, just hardcode settings for doing replication tests.
    struct(
      Worker.State,
      Map.put_new(
        settings,
        :step_context,
        Steps.Acstor.Replication.init_context()
      )
    )
  end

  def start_new_worker(%Worker.State{symbol: symbol} = worker_state) do
    # Start worker
    DynamicSupervisor.start_child(
      SymbolSupervisor.get_dynamic_worker_supervisor(symbol),
      Worker.child_spec(worker_state)
    )

    # Option 2
    # DynamicSupervisor.start_child(
    #     SymbolSupervisor.get_dynamic_worker_supervisor(symbol),
    #     {Worker, state}
    #   )
  end

  # Callback for restart failed worker due to some error when run a step.
  @impl true
  def handle_info(
        {:worker_step_error,
         %{
           which_module: which_module,
           which_function: which_function,
           step_output: step_output,
           worker_state: %{name: worker_name} = worker_state
         } = _error_context},
        %{symbol: symbol, workers: workers} = state
      ) do
    Logger.debug(
      "restart worker due to step error in #{which_module}.#{which_function}: #{step_output} for symbol: #{symbol}"
    )

    {:ok, new_worker_pid} = start_new_worker(worker_state)

    # update the worker name -- worker pid register
    updated_workers = Map.put(workers, worker_name, new_worker_pid)
    {:noreply, %{state | workers: updated_workers}}
  end

  # @impl true
  # def handle_info({:worker_in_progress, module_name, fun_name, "in_progress", nil}, state) do

  # end

  # Callback for get a worker's pid using a name.
  @impl true
  def handle_call({:get_worker_by_name, worker_name}, _from, %{workers: workers} = state) do
    case Map.get(workers, worker_name, nil) do
      nil ->
        {:reply, {:err, "worker #{worker_name} not exist"}, state}

      worker_pid ->
        if Process.alive?(worker_pid) do
          {:reply, {:ok, worker_pid}, state}
        else
          {:reply, {:err, "pid for worker #{worker_name} not alive"}, state}
        end
    end
  end

  @impl true
  def handle_call({:leader_state}, _from, state) do
    {:reply, state, state}
  end

  # Callback which indicate some worker is ready
  @impl true
  def handle_cast({:worker_is_ready, some_worker}, %{} = state) do
    Logger.info("Worker #{inspect(some_worker)} is ready")

    # GenServer.cast(some_worker, {:process_workflow, workflow})
    {:noreply, state}
  end

  # Interface functions
  def get_leader_pid_from_symbol(symbol) do
    worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

    case Process.alive?(worker_leader_pid) do
      true -> {:ok, worker_leader_pid}
      false -> {:err, "#{inspect(worker_leader_pid)} not alive"}
    end
  end

  def get_worker_by_name(symbol, worker_name) do
    worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

    case worker_leader_pid do
      nil ->
        Logger.error("There is no Worker.Leader for scenario: #{symbol}")

      pid ->
        GenServer.call(pid, {:get_worker_by_name, worker_name})
    end
  end

  def leader_state(symbol) do
    worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

    case worker_leader_pid do
      nil ->
        Logger.error("There is no Worker.Leader for scenario: #{symbol}")

      pid ->
        GenServer.call(pid, {:leader_state})
    end
  end
end
