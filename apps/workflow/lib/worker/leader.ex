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
              workflows_finished: [],
              symbol_execution_enabled: true
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
          workflows_in_progress: workflows_in_progress
        } = state
      ) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    %{
      worker_registry: updated_worker_registry,
      workflows_in_progress: updated_workflows_in_progress
    } =
      1..settings.n_workers
      |> Enum.to_list()
      |> Enum.reduce(
        %{worker_registry: worker_registry, workflows_in_progress: workflows_in_progress},
        fn _, acc ->
          start_one_fresh_worker_and_update_registry(%{
            worker_state: worker_state,
            workflows_in_progress: acc.workflows_in_progress,
            worker_registry: acc.worker_registry
          })
        end
      )

    {:noreply,
     %{
       state
       | settings: settings,
         worker_registry: updated_worker_registry,
         workflows_in_progress: updated_workflows_in_progress
     }}
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
           worker_pid: worker_pid,
           worker_state: worker_state
         } = _error_context},
        %{
          symbol: symbol,
          worker_registry: worker_registry,
          workflows_in_progress: workflows_in_progress
        } = state
      ) do
    Logger.debug(
      "restart worker due to step error in #{which_module}.#{which_function}: #{step_output} for symbol: #{symbol}"
    )

    # Find the corresponding workflow by first find the name
    {worker_name, _worker_pid} =
      worker_registry
      |> Enum.find(fn {_worker_name, pid} -> worker_pid == pid end)

    workflow = Map.get(workflows_in_progress, worker_name)

    case workflow do
      nil ->
        {:noreply, state}

      %{steps: steps} ->
        step_index =
          steps |> Enum.find_index(fn %{step_status: status} -> status == "in_progress" end)

        updated_step =
          Enum.at(steps, step_index)
          |> Map.put(:step_status, "failed")

        # TODO: check some policy service to see if there is retry defined for it.
        # If there is no retry remained, remove the workflow from workflow_in_progress to workflow_finished
        # Otherwise, keep it in the workflow_in_progress.

        updated_steps = List.replace_at(steps, step_index, updated_step)

        # TODO: rewrite this into one step.
        updated_workflow = %{workflow | steps: updated_steps}
        updated_workflows_in_progress = %{workflows_in_progress | worker_name => updated_workflow}

        {:ok, new_worker_pid} = start_new_worker(worker_state)

        # update the worker name -- worker pid register
        updated_worker_registry = Map.put(worker_registry, worker_name, new_worker_pid)

        {:noreply,
         %{
           state
           | worker_registry: updated_worker_registry,
             workflows_in_progress: updated_workflows_in_progress
         }}
    end
  end

  # Callback from worker to notice leader that the step from workflow is finished
  @impl true
  def handle_info(
        {:worker_step_finished,
         %{
           worker_pid: worker_pid,
           worker_name: worker_name,
           step_index: step_index,
           step_status: step_status
         }},
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_finished: workflows_finished,
          worker_registry: worker_registry
        } = state
      ) do
    # First, verify it is the worker we registered
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "Receive :worker_step_finished from unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored"
      )

      {:noreply, state}
    else
      %{steps: steps} = workflow = workflows_in_progress |> Map.get(worker_name)
      step_executed = Enum.at(steps, step_index)

      updated_steps =
        List.replace_at(steps, step_index, %{step_executed | step_status: step_status})

      updated_workflow = %{workflow | steps: updated_steps}

      case all_steps_finished(updated_steps) do
        true ->
          updated_workflows_finished = [updated_workflow | workflows_finished]
          updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, nil)

          {:noreply,
           %{
             state
             | workflows_finished: updated_workflows_finished,
               workflows_in_progress: updated_workflows_in_progress
           }}

        false ->
          updated_workflows_in_progress =
            Map.put(workflows_in_progress, worker_name, updated_workflow)

          {:noreply, %{state | workflows_in_progress: updated_workflows_in_progress}}
      end
    end
  end

  defp all_steps_finished(steps) do
    steps
    |> Enum.all?(fn %{step_status: step_status} -> step_status != "todo" end)
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
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(
        {:add_new_fresh_worker},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          worker_registry: worker_registry,
          symbol: symbol
        } = state
      ) do
    settings = fetch_symbol_settings(symbol)
    worker_state = fresh_worker_state(settings)

    updated_registory =
      start_one_fresh_worker_and_update_registry(%{
        worker_state: worker_state,
        workflows_in_progress: workflows_in_progress,
        worker_registry: worker_registry
      })

    {:reply, updated_registory, Map.merge(state, updated_registory)}
  end

  defp start_one_fresh_worker_and_update_registry(%{
         worker_state: worker_state,
         workflows_in_progress: workflows_in_progress,
         worker_registry: worker_registry
       }) do
    current_workers = worker_registry |> map_size()
    new_worker_name = "worker#{current_workers + 1}"
    {:ok, worker_pid} = Map.merge(worker_state, %{name: new_worker_name}) |> start_new_worker()

    updated_worker_registry = Map.put(worker_registry, new_worker_name, worker_pid)
    updated_workflows_in_progress = Map.put(workflows_in_progress, new_worker_name, nil)

    %{
      workflows_in_progress: updated_workflows_in_progress,
      worker_registry: updated_worker_registry
    }
  end

  @impl true
  def handle_call(
        {:toggle_symbol_execution},
        _from,
        %{symbol_execution_enabled: symbol_execution_enabled} = state
      ) do
    {:reply, not symbol_execution_enabled,
     %{state | symbol_execution_enabled: not symbol_execution_enabled}}
  end

  @impl true
  def handle_call({:add_workflows, workflows}, _from, %{workflows_todo: workflows_todo} = state) do
    {:reply, workflows, %{state | workflows_todo: workflows ++ workflows_todo}}
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

  # Callback to cancel workflow running on worker
  @impl true
  def handle_call(
        {:cancel_workflow, worker_name},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_finished: workflows_finished
        } = state
      ) do
    canceled_workflow = Map.get(workflows_in_progress, worker_name)
    updated_workflows_in_progress = %{workflows_in_progress | worker_name => nil}
    updated_workflows_finished = [canceled_workflow | workflows_finished]

    {:reply, canceled_workflow,
     %{
       state
       | workflows_in_progress: updated_workflows_in_progress,
         workflows_finished: updated_workflows_finished
     }}
  end

  @impl true
  def handle_call(
        {:execute_workflows},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          worker_registry: worker_registry
        } = state
      ) do
    # For each worker and its current workflow, run the next step which has status_todo

    updated_workflows_in_progress =
      workflows_in_progress
      |> Enum.map(fn {worker_name, %{steps: steps, workflow_id: workflow_id}} ->
        execute_workflows_aux(worker_registry, worker_name, workflow_id, steps)
      end)
      |> Map.new()

    {:reply, updated_workflows_in_progress,
     %{state | workflows_in_progress: updated_workflows_in_progress}}
  end

  defp execute_workflows_aux(worker_registry, worker_name, workflow_id, steps) do
    worker_pid = Map.get(worker_registry, worker_name)

    %{
      which_module: which_module,
      which_function: which_function,
      step_index: step_index,
      step_status: step_status,
      step_id: step_id
    } = next_todo_step = find_next_todo_step(steps)

    case step_status do
      x when x in ["todo", "failed"] ->
        Worker.run_step_with_id(%{
          worker_pid: worker_pid,
          worker_name: worker_name,
          which_module: which_module,
          which_function: which_function,
          step_index: step_index,
          step_id: step_id
        })

        updated_steps =
          List.replace_at(steps, step_index, %{next_todo_step | step_status: "in_progress"})

        {worker_name, %{steps: updated_steps, workflow_id: workflow_id}}

      "in_progress" ->
        {worker_name, %{steps: steps, workflow_id: workflow_id}}
    end
  end

  defp find_next_todo_step(steps) do
    steps
    |> Enum.find(fn %{step_status: status} ->
      status == "todo" or status == "in_progress" or status == "failed"
    end)
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

  def current_state(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:current_state})
  end

  def add_workflows_for_symbol(%{
        symbol: symbol,
        workflows_definition: [x | _rest] = workflows_definition
      })
      when is_list(x) do
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

  defp generate_steps(workflow_definition) when is_list(workflow_definition) do
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

  # A helper function to trigger Leader to run some workflow on some worker
  def schedule_workflows(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:schedule_workflows})
  end

  # A helper function to trigger each worker to run a todo step from its assigned workflow
  # It will update and return the latest workflows_in_progress
  def execute_workflows_for_symbol(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:execute_workflows})
  end

  # Cancel the workflow running on worker for some symbol
  def cancel_workflow(%{symbol: symbol, worker_name: worker_name}) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:cancel_workflow, worker_name})
  end

  def toggle_symbol_execution(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:toggle_symbol_execution})
  end

  def add_new_fresh_worker(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:add_new_fresh_worker})
  end
end
