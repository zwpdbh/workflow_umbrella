defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    use Accessible

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

  defmodule WorkflowInstance do
    use Accessible

    defstruct workflow_id: "",
              steps: [],
              workflow_status: ""
  end

  defmodule WorkflowStepState do
    use Accessible

    defstruct step_id: "",
              step_index: 0,
              step_status: "todo",
              which_function: "",
              which_module: ""
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    Logger.info("Initializing Worker.Leader for symbol: #{symbol}")
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
    leader_backup = Map.get(Worker.Collector.state_for_symbol(symbol), :leader_backup)

    case leader_backup do
      nil ->
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

      backup_state ->
        Worker.Collector.set_leader_state(%{
          symbol: symbol,
          leader_state: nil,
          reason: "leader reload its backup succeed, so reset its backup to empty"
        })

        {:noreply, backup_state}
    end
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

  defp process_failed_step_result(%{err: err, top_stacktrace: top_stacktrace} = _step_result) do
    case %{err: err, top_stacktrace: top_stacktrace} do
      %{
        err: {:badmatch, {:err, step_output}},
        top_stacktrace: {which_module, which_function, _arity, [file: _filename, line: _line_num]}
      } ->
        {Atom.to_string(which_module), Atom.to_string(which_function), step_output}

      %{
        err: :undef,
        top_stacktrace: {which_module, which_function, _}
      } ->
        {Atom.to_string(which_module), Atom.to_string(which_function), "undefined function"}

      _ ->
        {"unknow_module", "unknow_function", "top_stacktrace: #{inspect(top_stacktrace)}"}
    end
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

  defp find_next_step(steps) do
    steps
    |> Enum.find(fn %{step_status: status} ->
      status == "todo" or status == "in_progress" or status == "failed"
    end)
  end

  defp run_next_step_for_worker(worker_name, steps, %{worker_registry: worker_registry} = state) do
    worker_pid = Map.get(worker_registry, worker_name)

    next_step = find_next_step(steps)

    case next_step do
      nil ->
        state

      next_step ->
        case next_step.step_status do
          x when x in ["todo", "failed"] ->
            Worker.run_step_with_id(
              Map.merge(next_step, %{worker_pid: worker_pid, worker_name: worker_name})
            )

            # update workflows_in_progress
            updated_steps =
              List.replace_at(steps, next_step.step_index, %{
                next_step
                | step_status: "in_progress"
              })

            put_in(state, [:workflows_in_progress, worker_name, :steps], updated_steps)

          "in_progress" ->
            # If previous step still in progress, we keep don't do anything
            state
        end
    end
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
        {:add_new_worker},
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

  @impl true
  def handle_call(
        {:schedule_workflow_for_worker, worker_name, :prepare_next_todo_step},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_todo: workflows_todo,
          workflows_finished: workflows_finished
        } = state
      ) do
    case {Map.get(workflows_in_progress, worker_name), workflows_todo} do
      {nil, []} ->
        {:reply, nil, state}

      {nil, [head | rest]} ->
        updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, head)

        {:reply, head,
         %{state | workflows_in_progress: updated_workflows_in_progress, workflows_todo: rest}}

      {%{steps: steps} = current_workflow, []} ->
        if find_next_step(steps) != nil do
          {:reply, current_workflow, state}
        else
          # If there is no more available steps to execut in current workflow's steps and no new workflows
          # This is the case all workflows are finished
          updated_workflows_finished = [
            Map.put(current_workflow, :workflow_status, "succeed") | workflows_finished
          ]

          updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, nil)
          Logger.info("There is no more workflows to be executed for worker: #{worker_name}")

          {:reply, nil,
           %{
             state
             | workflows_in_progress: updated_workflows_in_progress,
               workflows_finished: updated_workflows_finished
           }}
        end

      {%{steps: steps} = current_workflow, [head | rest]} ->
        if find_next_step(steps) != nil do
          {:reply, current_workflow, state}
        else
          # If there is no more available steps to execut in current workflow's steps,
          # we schedule a new one and move current one into finished
          updated_workflows_finished = [
            Map.put(current_workflow, :workflow_status, "succeed") | workflows_finished
          ]

          updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, head)

          {:reply, head,
           %{
             state
             | workflows_in_progress: updated_workflows_in_progress,
               workflows_todo: rest,
               workflows_finished: updated_workflows_finished
           }}
        end
    end
  end

  @impl true
  def handle_call(
        {:schedule_workflow_for_worker, worker_name, :terminate_workflow},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_todo: workflows_todo,
          workflows_finished: workflows_finished
        } = state
      ) do
    # Terminate the current workflow and move it to finished
    # And move a new workflow for it.
    case {Map.get(workflows_in_progress, worker_name), workflows_todo} do
      {nil, []} ->
        {:reply, nil, state}

      {nil, [head | rest]} ->
        updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, head)

        {:reply, head,
         %{state | workflows_in_progress: updated_workflows_in_progress, workflows_todo: rest}}

      {%{steps: _steps} = current_workflow, []} ->
        updated_workflows_finished = [
          Map.put(current_workflow, :workflow_status, "terminated") | workflows_finished
        ]

        updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, nil)

        {:reply, nil,
         %{
           state
           | workflows_in_progress: updated_workflows_in_progress,
             workflows_finished: updated_workflows_finished
         }}

      {%{steps: _steps} = current_workflow, [head | rest]} ->
        updated_workflows_finished = [
          Map.put(current_workflow, :workflow_status, "terminated") | workflows_finished
        ]

        updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, head)

        {:reply, head,
         %{
           state
           | workflows_in_progress: updated_workflows_in_progress,
             workflows_todo: rest,
             workflows_finished: updated_workflows_finished
         }}
    end
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
  def handle_cast(
        {:execute_workflow_for_worker, worker_name},
        %{
          workflows_in_progress: workflows_in_progress,
          symbol_execution_enabled: enabled
        } = state
      ) do
    case {enabled, Map.get(workflows_in_progress, worker_name)} do
      {false, _} ->
        {:noreply, state}

      {true, nil} ->
        Logger.debug(
          "#{__MODULE__} in handle_cast :execute_workflow_for_worker: #{worker_name}. But there is no associated workflow for this worker, need to schedule a workflow for it first."
        )

        {:noreply, state}

      {true, %{steps: steps}} ->
        updated_state = run_next_step_for_worker(worker_name, steps, state)
        {:noreply, updated_state}

      {_, _} ->
        # Default one
        Logger.debug("#{__MODULE__} in handle_cast :execute_workflow_for_worker, unexpected")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:worker_step_succeed, %{worker_name: worker_name, worker_pid: worker_pid} = step_result},
        %{worker_registry: worker_registry, workflows_in_progress: workflows_in_progress} = state
      ) do
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "Receive :worker_step_succeed from unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored"
      )

      worker_registry |> IO.inspect(label: "#{__MODULE__} 338")

      {:noreply, state}
    else
      workflow = workflows_in_progress |> Map.get(worker_name)

      %{which_module: which_module, which_function: which_function} =
        step_executed = Enum.at(workflow.steps, step_result.step_index)

      updated_steps =
        List.replace_at(workflow.steps, step_result.step_index, %{
          step_executed
          | step_status: "succeed"
        })

      Logger.info(
        "#{worker_name} execute step:#{step_result.step_index} succeed for #{which_module}.#{which_function}"
      )

      updated_state = put_in(state, [:workflows_in_progress, worker_name, :steps], updated_steps)
      {:noreply, updated_state}
    end
  end

  @impl true
  def handle_cast(
        {:worker_step_failed,
         %{worker_name: worker_name, worker_pid: worker_pid, worker_state: worker_state} =
           step_result},
        %{worker_registry: worker_registry, workflows_in_progress: workflows_in_progress} = state
      ) do
    {:noreply, state}
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "Receive :worker_step_failed from unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored"
      )

      {:noreply, state}
    else
      # Find out which step failed from which workflow
      workflow = Map.get(workflows_in_progress, worker_name)

      # The failed step must come from a step which is still in "in_progress" status
      index_for_step_in_progress =
        workflow.steps
        |> Enum.find_index(fn %{step_status: status} -> status == "in_progress" end)

      # update the step status
      step_executed = Enum.at(workflow.steps, index_for_step_in_progress)
      # update the workflow steps
      updated_steps =
        List.replace_at(workflow.steps, index_for_step_in_progress, %{
          step_executed
          | step_status: "failed"
        })

      # Need to restart a new worker
      crashed_worker_state = step_result.worker_state
      step_failure_history = process_failed_step_result(step_result)

      # the new worker will contain updated history to include the failed step
      updated_worker_state = %{
        worker_state
        | history: [step_failure_history | crashed_worker_state.history]
      }

      {:ok, new_worker_pid} = start_new_worker(updated_worker_state)

      # update the worker name -- worker pid register
      updated_worker_registry = Map.put(worker_registry, worker_name, new_worker_pid)

      updated_state = put_in(state, [:workflows_in_progress, worker_name, :steps], updated_steps)
      updated_state = put_in(updated_state, [:worker_registry], updated_worker_registry)

      {:noreply, updated_state}
    end
  end

  # Callback which indicate some worker is ready
  @impl true
  def handle_cast({:worker_is_ready, some_worker}, %{} = state) do
    Logger.info("Worker #{inspect(some_worker)} is ready")

    # GenServer.cast(some_worker, {:process_workflow, workflow})
    {:noreply, state}
  end

  # Callback for handling temrination of Leader
  @impl true
  def terminate(_reason, %{symbol: symbol} = state) do
    Worker.Collector.set_leader_state(%{
      symbol: symbol,
      leader_state: state,
      reason: "leader crashed"
    })
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

  def schedule_workflows(symbol) do
    %{worker_registry: worker_registry} = current_state(symbol)

    worker_registry
    |> Enum.map(fn {worker_name, _worker_pid} ->
      scheduled_workflow =
        schedule_workflow_for_worker(%{
          symbol: symbol,
          worker_name: worker_name,
          schedule: :prepare_next_todo_step
        })

      {worker_name, scheduled_workflow}
    end)
    |> Map.new()
  end

  # A helper function to trigger Leader to run some workflow on some worker
  def schedule_workflow_for_worker(%{
        symbol: symbol,
        worker_name: worker_name,
        schedule: how_to_schedule
      }) do
    GenServer.call(
      :"#{__MODULE__}_#{symbol}",
      {:schedule_workflow_for_worker, worker_name, how_to_schedule}
    )
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

  # A helper function to trigger each worker to run a todo step from its assigned workflow
  # It will update and return the latest workflows_in_progress
  def execute_workflows_for_symbol(symbol) do
    %{
      worker_registry: worker_registry
    } = current_state(symbol)

    worker_registry
    |> Enum.each(fn {worker_name, _worker_pid} ->
      execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name})
    end)

    updated_state = current_state(symbol)
    updated_state.workflows_in_progress
  end

  # Cancel the workflow running on worker for some symbol
  def cancel_workflow(%{symbol: symbol, worker_name: worker_name}) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:cancel_workflow, worker_name})
  end

  def toggle_symbol_execution(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:toggle_symbol_execution})
  end

  def add_new_worker(symbol) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:add_new_worker})
  end

  def execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name}) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:execute_workflow_for_worker, worker_name})
  end

  def worker_step_succeed(%{symbol: symbol} = result) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:worker_step_succeed, result})
  end

  def worker_step_failed(%{symbol: symbol} = result) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:worker_step_failed, result})
  end
end
