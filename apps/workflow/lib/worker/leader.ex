defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    defstruct symbol: nil,
              settings: nil,
              # worker_registry contains the mapping (k, v) where k is the worker_name, v is the worker_pid
              worker_registry: %{},
              # workflows_in_progress is map(k, v) where k is the worker_name, v is one workflow %{workflow_id: xx, steps: [aa, bb,cc]}
              # aa is %{}
              workflows_in_progress: %{},
              workflows_todo: [],
              workflows_finished: []
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    {:ok, %State{symbol: symbol, worker_registry: %{}}, {:continue, :init_workers}}
  end

  @impl true
  def handle_continue(
        :init_workers,
        %{
          symbol: symbol,
          worker_registry: worker_registry,
          workflows_in_progress: workflow_in_progress
        } = state
      ) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    updated_worker_registry =
      init_worker_registry(settings.n_workers, worker_registry, worker_state)

    updated_workflows_in_progress =
      init_workflows_in_progress(settings.n_workers, workflow_in_progress)

    {:noreply,
     %{
       state
       | settings: settings,
         worker_registry: updated_worker_registry,
         workflows_in_progress: updated_workflows_in_progress
     }}

    # {:noreply, %{state | settings: settings}}
  end

  # We shall maintain our own worker registering logic
  # Do not name process create dynamically (do not naming worker process)
  defp init_worker_registry(n_workers, worker_registry, worker_state) do
    1..n_workers
    |> Enum.to_list()
    |> Enum.reduce(
      worker_registry,
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
  end

  defp init_workflows_in_progress(n_workers, workflow_in_progress) do
    1..n_workers
    |> Enum.to_list()
    |> Enum.reduce(
      workflow_in_progress,
      fn index, acc ->
        Map.put(acc, "worker#{index}", nil)
      end
    )
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
        %{symbol: symbol, worker_registry: worker_registry} = state
      ) do
    Logger.debug(
      "restart worker due to step error in #{which_module}.#{which_function}: #{step_output} for symbol: #{symbol}"
    )

    {:ok, new_worker_pid} = start_new_worker(worker_state)

    # update the worker name -- worker pid register
    updated_worker_registry = Map.put(worker_registry, worker_name, new_worker_pid)
    {:noreply, %{state | worker_registry: updated_worker_registry}}
  end

  # Callback for get a worker's pid using a name.
  @impl true
  def handle_call(
        {:get_worker_by_name, worker_name},
        _from,
        %{worker_registry: worker_registry} = state
      ) do
    case Map.get(worker_registry, worker_name, nil) do
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

  @impl true
  def handle_call({:add_workflows, workflows}, _from, %{workflows_todo: workflows_todo} = state) do
    {:reply, workflows, %{state | workflows_todo: [workflows] ++ workflows_todo}}
  end

  # Callback for schedule workflows on available workers
  @impl true
  def handle_call(
        {:schedule_workflows},
        _from,
        %{workflows_in_progress: workflows_in_progress, workflows_todo: workflows_todo} = state
      ) do
    # Find available workers
    available_workers =
      workflows_in_progress
      |> Map.to_list()
      |> Enum.filter(fn {_worker_name, workflow} -> workflow == nil end)
      |> Enum.map(fn {worker_name, nil} -> worker_name end)

    assigned_workers_with_workflows =
      Enum.zip(available_workers, workflows_todo)
      |> Enum.reduce(%{}, fn {k, v}, acc -> Map.put(acc, k, v) end)

    # Remove assigned workflows from workflows_todo
    updated_workflows_todo =
      workflows_todo |> Enum.drop(map_size(assigned_workers_with_workflows))

    # Merge old one with new one
    updated_workflows_in_progress =
      Map.merge(workflows_in_progress, assigned_workers_with_workflows)

    {:reply, assigned_workers_with_workflows,
     %{
       state
       | workflows_todo: updated_workflows_todo,
         workflows_in_progress: updated_workflows_in_progress
     }}
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
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:leader_state})
  end

  def add_workflows_for_symbol(%{symbol: symbol, workflows_definition: workflows_definition})
      when is_list(workflows_definition) do
    workflows =
      workflows_definition
      |> Enum.map(fn each_workflow_definition ->
        workflow_id = Ecto.UUID.generate()
        steps = generate_steps(each_workflow_definition)

        %{workflow_id: workflow_id, steps: steps}
      end)

    GenServer.call(:"#{__MODULE__}_#{symbol}", {:add_workflows, workflows})
  end

  def add_workflow_for_symbol(%{symbol: symbol, workflow_definition: workflow}) do
    add_workflows_for_symbol(%{symbol: symbol, workflows_definition: [workflow]})
  end

  def generate_steps(workflow_definition) when is_list(workflow_definition) do
    workflow_definition
    |> Enum.with_index()
    |> Enum.map(fn {{which_module, which_function}, index} ->
      %{
        step_index: index,
        step_id: Ecto.UUID.generate(),
        step_status: "todo",
        which_module: which_module,
        which_function: which_function
      }
    end)
  end

  # An helper function to trigger Leader to run some workflow on some worker
  def schedule_workflows(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:schedule_workflows})
  end
end
