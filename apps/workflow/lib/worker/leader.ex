defmodule Worker.Leader do
  use GenServer
  require Logger

  defmodule State do
    use Accessible

    defstruct symbol: nil,
              setting: nil,
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
              workflow_status: "todo",
              log_file: "",
              step_context: %{}
  end

  defmodule WorkflowStepState do
    use Accessible

    defstruct step_id: "",
              step_index: 0,
              step_status: "todo",
              which_function: "",
              which_module: "",
              retry_count: 0
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
        symbol_setting = fetch_symbol_settings(symbol)

        %{
          worker_registry: updated_worker_registry,
          workflows_in_progress: updated_workflows_in_progress
        } =
          1..symbol_setting.n_workers
          |> Enum.to_list()
          |> Enum.reduce(
            %{worker_registry: worker_registry, workflows_in_progress: workflows_in_progress},
            fn _, acc ->
              %{
                worker_name: worker_name,
                worker_pid: worker_pid
              } =
                start_one_fresh_worker(%{
                  symbol_setting: symbol_setting,
                  workflows_in_progress: acc.workflows_in_progress,
                  worker_registry: acc.worker_registry
                })

              updated_worker_registry = Map.put(acc.worker_registry, worker_name, worker_pid)
              updated_workflows_in_progress = Map.put(acc.workflows_in_progress, worker_name, nil)

              %{
                worker_registry: updated_worker_registry,
                workflows_in_progress: updated_workflows_in_progress
              }
            end
          )

        {:noreply,
         %{
           state
           | setting: symbol_setting,
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

  def start_new_worker_with_state(%Worker.State{symbol: symbol, name: worker_name} = worker_state) do
    # Start worker
    {:ok, worker_pid} =
      DynamicSupervisor.start_child(
        SymbolSupervisor.get_dynamic_worker_supervisor(symbol),
        Worker.child_spec(worker_state)
      )

    %{
      worker_name: worker_name,
      worker_pid: worker_pid
    }

    # Option 2
    # DynamicSupervisor.start_child(
    #     SymbolSupervisor.get_dynamic_worker_supervisor(symbol),
    #     {Worker, state}
    #   )
  end

  defp start_one_fresh_worker(%{
         symbol_setting: symbol_setting
       }) do
    %{step_context: %{suffix: suffix}} = worker_state = fresh_worker_state(symbol_setting)

    new_worker_name = "worker_#{suffix}"
    new_worker_state = Map.put(worker_state, :name, new_worker_name)

    new_worker_state |> start_new_worker_with_state()
  end

  defp find_next_step(steps) do
    steps
    |> Enum.find(fn %{step_status: status} ->
      status == "todo" or status == "in_progress" or status == "failed"
    end)
  end

  defp decide_workflow_status_from_steps(steps) do
    all_todo? =
      steps
      |> Enum.all?(fn %{step_status: status} -> status == "todo" end)

    all_succeed? =
      steps
      |> Enum.all?(fn %{step_status: status} -> status == "succeed" end)

    any_failed? =
      steps
      |> Enum.any?(fn %{step_status: status} -> status == "failed" end)

    # any_in_progress? =
    #   steps
    #   |> Enum.any?(fn %{step_status: status} -> status == "in_progress" end)

    case {all_succeed?, any_failed?, all_todo?} do
      {true, _, _} -> "succeed"
      {_, true, _} -> "failed"
      {_, _, true} -> "todo"
      _ -> "in_progress"
    end
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
    symbol_setting = fetch_symbol_settings(symbol)

    %{worker_name: new_worker_name, worker_pid: new_worker_pid} =
      created_worker_info =
      start_one_fresh_worker(%{
        symbol_setting: symbol_setting,
        workflows_in_progress: workflows_in_progress,
        worker_registry: worker_registry
      })

    updated_worker_registry = Map.put(worker_registry, new_worker_name, new_worker_pid)
    updated_workflows_in_progress = Map.put(workflows_in_progress, new_worker_name, nil)

    {:reply, created_worker_info,
     %{
       state
       | workflows_in_progress: updated_workflows_in_progress,
         worker_registry: updated_worker_registry
     }}
  end

  @impl true
  def handle_call(
        {:terminate_worker, worker_name},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_finished: workflows_finished,
          worker_registry: worker_registry,
          symbol: symbol
        } = state
      ) do
    worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != nil do
      DynamicSupervisor.terminate_child(
        SymbolSupervisor.get_dynamic_worker_supervisor(symbol),
        worker_pid
      )

      workflow_finished = Map.get(workflows_in_progress, worker_name)

      updated_workflows_finished = [workflow_finished | workflows_finished]
      updated_workflows_in_progress = Map.delete(workflows_in_progress, worker_name)
      updated_worker_registry = Map.delete(worker_registry, worker_name)

      Logger.info(
        "#{__MODULE__} terminate_worker for #{worker_name} because it finished one workflow succeed"
      )

      {:reply, {:ok, worker_pid},
       %{
         state
         | workflows_in_progress: updated_workflows_in_progress,
           workflows_finished: updated_workflows_finished,
           worker_registry: updated_worker_registry
       }}
    else
      Logger.warn(
        "Try to terminate worker: #{worker_name} for symbol: #{symbol}, but #{worker_name} is not registered. Do nothing."
      )

      {:reply, {:err, "worker: #{worker_name} not registered for symbol: #{symbol}"}, state}
    end
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
        {:schedule_workflow_for_worker, worker_name, :next_workflow},
        _from,
        %{
          workflows_in_progress: workflows_in_progress,
          workflows_todo: workflows_todo,
          workflows_finished: workflows_finished,
          worker_registry: worker_registry
        } = state
      ) do
    current_workflow = Map.get(workflows_in_progress, worker_name)

    case {current_workflow, workflows_todo} do
      {nil, []} ->
        {:reply, nil, state}

      {nil, [head | rest]} ->
        worker_pid = Map.get(worker_registry, worker_name)

        if worker_pid == nil do
          Logger.debug(
            "#{__MODULE__} schedule_workflow_for_worker but there is no worker registered for #{worker_name}"
          )

          {:reply, {:err, "not registered worker send schedule workflow request"}, state}
        else
          %{step_context: %{log_file: log_file}} =
            _worker_state = Worker.worker_state(worker_registry[worker_name])

          scheduled_workflow = head |> Map.put(:log_file, log_file)

          updated_workflows_in_progress =
            Map.put(workflows_in_progress, worker_name, scheduled_workflow)

          {:reply, {:ok, scheduled_workflow},
           %{state | workflows_in_progress: updated_workflows_in_progress, workflows_todo: rest}}
        end

      {%{steps: steps}, []} ->
        if decide_workflow_status_from_steps(steps) == "todo" do
          {:reply, {:ok, current_workflow}, state}
        else
          Logger.info("There is no more workflows to be executed for worker: #{worker_name}")
          updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, nil)

          workflow_status = decide_workflow_status_from_steps(steps)

          updated_workflows_finished = [
            Map.put(current_workflow, :workflow_status, workflow_status) | workflows_finished
          ]

          {:reply, {:err, "no more workflows in todo"},
           %{
             state
             | workflows_in_progress: updated_workflows_in_progress,
               workflows_finished: updated_workflows_finished
           }}
        end

      {%{steps: steps}, [head | rest]} ->
        if decide_workflow_status_from_steps(steps) == "todo" do
          {:reply, {:ok, current_workflow}, state}
        else
          updated_workflows_in_progress = Map.put(workflows_in_progress, worker_name, head)

          workflow_status = decide_workflow_status_from_steps(steps)

          updated_workflows_finished = [
            Map.put(current_workflow, :workflow_status, workflow_status) | workflows_finished
          ]

          {:reply, {:ok, head},
           %{
             state
             | workflows_in_progress: updated_workflows_in_progress,
               workflows_finished: updated_workflows_finished,
               workflows_todo: rest
           }}
        end
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
  def handle_call(
        {:worker_step_succeed,
         %{worker_name: worker_name, worker_pid: worker_pid, step_context: step_context} =
           step_result},
        _from,
        %{
          worker_registry: worker_registry,
          workflows_in_progress: workflows_in_progress
        } = state
      ) do
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "Receive :worker_step_succeed from unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored. The current worker_registry is #{inspect(worker_registry)}"
      )

      worker_registry |> IO.inspect(label: "#{__MODULE__} 338")
      {:noreply, :ignore, state}
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

      updated_state =
        put_in(updated_state, [:workflows_in_progress, worker_name, :step_context], step_context)

      # update workflow status
      updated_state =
        put_in(
          updated_state,
          [:workflows_in_progress, worker_name, :workflow_status],
          decide_workflow_status_from_steps(updated_steps)
        )

      case find_next_step(updated_steps) do
        nil ->
          # If there is no next step for current workflow, we need to move the workflow into finished one
          {:reply, :schedule_next_workflow, updated_state}

        _ ->
          {:reply, :execute_next_step, updated_state}
      end
    end
  end

  @impl true
  def handle_call(
        {:worker_step_failed,
         %{
           worker_name: worker_name,
           worker_pid: worker_pid,
           worker_state: %{step_context: step_context} = _crashed_worker_state
         } = _step_result},
        _from,
        %{
          worker_registry: worker_registry,
          workflows_in_progress: workflows_in_progress
        } = state
      ) do
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "Receive :worker_step_failed from unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored. The current worker_registry is #{inspect(worker_registry)}"
      )

      {:reply, :ignore, state}
    else
      # Find out which step failed from which workflow
      workflow = Map.get(workflows_in_progress, worker_name)

      # The failed step must come from a step which is still in "in_progress" status
      index_for_step_in_progress =
        workflow.steps
        |> Enum.find_index(fn %{step_status: status} -> status == "in_progress" end)

      # update the step status
      %{which_module: which_module, which_function: which_function, retry_count: retry_count} =
        step_executed = Enum.at(workflow.steps, index_for_step_in_progress)

      # update the workflow steps
      maximum_retry = Steps.Acstor.WorkflowConfig.retry_policy(which_function)

      updated_state =
        put_in(state, [:workflows_in_progress, worker_name, :step_context], step_context)

      # Retry logic is implemented in this callback for handling step failure.
      case retry_count < maximum_retry do
        true ->
          Logger.info(
            "#{__MODULE__} worker_step_failed: worker_name -- #{worker_name}, step -- step:#{index_for_step_in_progress}, function -- #{which_module}.#{which_function}, retry -- #{retry_count}/#{maximum_retry}"
          )

          updated_steps =
            List.replace_at(workflow.steps, index_for_step_in_progress, %{
              step_executed
              | step_status: "failed",
                retry_count: retry_count + 1
            })

          # We only updated the step status for the failed step.
          updated_state =
            put_in(updated_state, [:workflows_in_progress, worker_name, :steps], updated_steps)

          updated_state =
            put_in(
              updated_state,
              [:workflows_in_progress, worker_name, :workflow_status],
              "in_retry"
            )

          {:reply, :repaire_worker_and_retry_step, updated_state}

        false ->
          # We reach retry limit for that step
          Logger.info(
            "#{__MODULE__} worker_step_failed reach retry limit: worker_name -- #{worker_name}, step -- step:#{index_for_step_in_progress}, function -- #{which_module}.#{which_function}, retry -- #{retry_count}/#{maximum_retry}"
          )

          updated_steps =
            List.replace_at(workflow.steps, index_for_step_in_progress, %{
              step_executed
              | step_status: "failed"
            })

          # We only updated the step status for the failed step.
          updated_state =
            put_in(updated_state, [:workflows_in_progress, worker_name, :steps], updated_steps)

          # update workflow status
          updated_state =
            put_in(
              updated_state,
              [:workflows_in_progress, worker_name, :workflow_status],
              decide_workflow_status_from_steps(updated_steps)
            )

          {:reply, :skip_and_schedule_next_workflow, updated_state}
      end
    end
  end

  # This this callback we start new worker and register it and it inherits the previous crashed worker's state.
  @impl true
  def handle_call(
        {:repaire_worker_from_step_result,
         %{worker_name: worker_name, worker_pid: worker_pid, worker_state: worker_state} =
           step_result},
        _from,
        %{
          worker_registry: worker_registry
        } = state
      ) do
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "#{__MODULE__} repaire_worker_and_retry_step for unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored. The current worker_registry is #{inspect(worker_registry)}"
      )

      {:reply, :ignore, state}
    else
      # We need to start a new worker to hold(update) the crashed worker's history.
      crashed_worker_state = step_result.worker_state
      step_failure_history = process_failed_step_result(step_result)

      # the new worker will contain updated history to include the failed step
      updated_worker_state = %{
        worker_state
        | history: [step_failure_history | crashed_worker_state.history]
      }

      %{worker_name: new_worker_name, worker_pid: new_worker_pid} =
        start_new_worker_with_state(updated_worker_state)

      # update the worker name -- worker pid register
      updated_worker_registry = Map.put(worker_registry, new_worker_name, new_worker_pid)
      updated_state = put_in(state, [:worker_registry], updated_worker_registry)

      {:reply, :ok, updated_state}
    end
  end

  # cleanup_worker_from_step_result is different from repaire_worker_from_step_result such that:
  # In repaire_worker_from_step_result, a new worker is started.
  # In cleanup_worker_from_step_result, we
  # 1) delete not valid worker_name <-> worker_pid registry (the worker is crashed)
  # 2) move workflows_in_progress into finished (don't need to update the step caused worker crash because we did it in worker_step_failed callback)
  # 3) delete workflows_in_progress related with crashed_worker_name
  @impl true
  def handle_call(
        {:cleanup_worker_from_step_result,
         %{worker_name: worker_name, worker_pid: worker_pid} = _step_result},
        _from,
        %{
          worker_registry: worker_registry,
          workflows_in_progress: workflows_in_progress,
          workflows_finished: workflows_finished
        } = state
      ) do
    registered_worker_pid = Map.get(worker_registry, worker_name)

    if worker_pid != registered_worker_pid do
      Logger.warn(
        "#{__MODULE__} repaire_worker_and_retry_step for unknow worker: #{inspect(Map.get(worker_registry, worker_name))}, ignored. The current worker_registry is #{inspect(worker_registry)}"
      )

      {:reply, :ignore, state}
    else
      # 1) delete not valid worker_name <-> worker_pid registry (the worker is crashed)
      updated_worker_registry = Map.delete(worker_registry, worker_name)
      # 2) move workflows_in_progress into finished
      updated_workflows_finished = [
        Map.get(workflows_in_progress, worker_name) | workflows_finished
      ]

      # 3) delete workflows_in_progress related with crashed_worker_name
      updated_workflows_in_progress = Map.delete(workflows_in_progress, worker_name)

      {:reply, :ok,
       %{
         state
         | worker_registry: updated_worker_registry,
           workflows_in_progress: updated_workflows_in_progress,
           workflows_finished: updated_workflows_finished
       }}
    end
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

  # Callback which indicate some worker is ready
  @impl true
  def handle_cast(
        {:worker_is_ready, %{worker_name: worker_name, worker_pid: worker_pid}},
        %{} = state
      ) do
    Logger.info("Worker: #{worker_name} -- #{inspect(worker_pid)} is ready")

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
          schedule_method: :next_workflow
        })

      {worker_name, scheduled_workflow}
    end)
    |> Map.new()
  end

  # A helper function to trigger Leader to run some workflow on some worker
  def schedule_workflow_for_worker(%{
        symbol: symbol,
        worker_name: worker_name,
        schedule_method: how_to_schedule
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
        which_function: which_function,
        retry_count: 0
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

  def terminate_worker(%{symbol: symbol, worker_name: worker_name}) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:terminate_worker, worker_name})
  end

  def execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name}) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:execute_workflow_for_worker, worker_name})
  end

  def worker_step_succeed(%{symbol: symbol} = result) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:worker_step_succeed, result})
  end

  def worker_step_failed(%{symbol: symbol} = result) do
    GenServer.call(:"#{__MODULE__}_#{symbol}", {:worker_step_failed, result})
  end

  def repaire_worker_from_step_result(%{symbol: symbol} = result) do
    GenServer.call(
      :"#{__MODULE__}_#{symbol}",
      {:repaire_worker_from_step_result, result}
    )
  end

  def cleanup_worker_from_step_result(%{symbol: symbol} = result) do
    GenServer.call(
      :"#{__MODULE__}_#{symbol}",
      {:cleanup_worker_from_step_result, result}
    )
  end

  # def repaire_worker_and_retry_step(%{symbol: symbol} = result, retry_remained)
  #     when is_integer(retry_remained) do
  #   GenServer.call(
  #     :"#{__MODULE__}_#{symbol}",
  #     {:repaire_worker_and_retry_step, result, retry_remained}
  #   )
  # end
end
