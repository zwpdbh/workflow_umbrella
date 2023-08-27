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
          Map.put(acc, "worker#{index}", start_new_worker(worker_state))
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

  def start_new_worker(%Worker.State{symbol: symbol} = state) do
    DynamicSupervisor.start_child(
      :"DynamicWorkerSupervisor_#{symbol}",
      {Worker, state}
    )
  end

  # @impl true
  # def handle_call({:execute_workflows, workflows}, _pid, %{workflows: current_workflows} = state) do
  #   updated_workflows = config_workflows(workflows) ++ current_workflows

  #   # After Leader got new workflows, how to envoke workers?
  #   # Some workers are ready but got no workflows.
  #   # TODO:
  #   # We could ask each worker to report themselves.

  #   {:reply, {:ok, workflows |> length}, %{state | workflows: updated_workflows}}
  # end

  # defp config_workflows(workflows) do
  #   workflows
  #   |> Enum.map(fn each -> %{steps: each, id: UUID.uuid1(), status: :not_start_yet} end)
  # end

  @impl true
  def handle_call({:get_worker_by_name, worker_name}, _from, %{workers: workers} = state) do
    case Map.get(workers, worker_name, nil) do
      nil -> {:reply, {:err, "worker #{worker_name}not exist"}, state}
      {:ok, worker_pid} -> {:reply, {:ok, worker_pid}, state}
    end
  end

  # @impl true
  # def handle_call({:workflow_is_finished, workflow_id}, worker_pid, state) do
  #   Logger.info("Worker #{inspect(worker_pid)} finished workflow: #{workflow_id}")
  #   {:reply, :ok, state}
  # end

  # @impl true
  # def handle_call({:workflow_status}, _from, %{workflows: workflows} = state) do
  #   {:reply, {:ok, workflows}, state}
  # end

  @impl true
  def handle_cast({:worker_is_ready, some_worker}, %{} = state) do
    Logger.info("Worker #{inspect(some_worker)} is ready")

    # GenServer.cast(some_worker, {:process_workflow, workflow})
    {:noreply, state}
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

  # @impl true
  # def handle_cast(
  #       {:worker_is_ready, some_worker},
  #       %{workflows: [%{id: workflow_id} = workflow | rest]} = state
  #     ) do
  #   Logger.info("Worker #{inspect(some_worker)} is ready, assign workflow #{workflow_id} to it")

  #   GenServer.cast(some_worker, {:process_workflow, workflow})
  #   {:noreply, %{state | workflows: rest}}
  # end

  # def workflow_status(symbol) do
  #   worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

  #   case worker_leader_pid do
  #     nil ->
  #       Logger.error("There is no Worker.Leader for scenario: #{symbol}")

  #     pid ->
  #       GenServer.call(pid, {:workflow_status})
  #   end
  # end
end
