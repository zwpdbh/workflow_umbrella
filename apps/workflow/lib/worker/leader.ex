defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              workers: [],
              workflows: []
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
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

  @impl true
  def handle_call({:execute_workflows, workflows}, _pid, %{workflows: current_workflows} = state) do
    updated_workflows = config_workflows(workflows) ++ current_workflows

    # After Leader got new workflows, how to envoke workers?
    # Some workers are ready but got no workflows.
    # TODO:
    # We could ask each worker to report themselves.

    {:reply, {:ok, workflows |> length}, %{state | workflows: updated_workflows}}
  end

  @impl true
  def handle_call({:workflow_is_finished, workflow_id}, worker_pid, state) do
    Logger.info("Worker #{inspect(worker_pid)} finished workflow: #{workflow_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:workflow_status}, _from, %{workflows: workflows} = state) do
    {:reply, {:ok, workflows}, state}
  end

  defp config_workflows(workflows) do
    workflows
    |> Enum.map(fn each -> %{steps: each, id: UUID.uuid1(), status: :not_start_yet} end)
  end

  @impl true
  def handle_cast({:worker_is_ready, some_worker}, %{workflows: []} = state) do
    Logger.info(
      "Worker #{inspect(some_worker)} is ready, there are currently 0 workflows to be executed"
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:worker_is_ready, some_worker},
        %{workflows: [%{id: workflow_id} = workflow | rest]} = state
      ) do
    Logger.info("Worker #{inspect(some_worker)} is ready, assign workflow #{workflow_id} to it")

    GenServer.cast(some_worker, {:process_workflow, workflow})
    {:noreply, %{state | workflows: rest}}
  end

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
    DynamicSupervisor.start_child(
      :"DynamicWorkerSupervisor_#{symbol}",
      {Worker, state}
    )
  end

  def execute_workflows(symbol, workflows) do
    worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

    case worker_leader_pid do
      nil ->
        Logger.error("There is no Worker.Leader for scenario: #{symbol}")

      pid ->
        GenServer.call(pid, {:execute_workflows, workflows})
    end
  end

  def workflow_status(symbol) do
    worker_leader_pid = Process.whereis(:"Elixir.Worker.Leader_#{symbol}")

    case worker_leader_pid do
      nil ->
        Logger.error("There is no Worker.Leader for scenario: #{symbol}")

      pid ->
        GenServer.call(pid, {:workflow_status})
    end
  end
end
