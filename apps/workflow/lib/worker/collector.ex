defmodule Worker.Collector do
  use GenServer

  require Logger

  @moduledoc """
  This module is used to collector the state changes of Worker.Leader.
  We trigger extra event to leader.
  """

  defmodule State do
    defstruct symbol: nil,
              leader_backup: nil
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    Logger.info("Initializing Worker.Collector for symbol: #{symbol}")
    {:ok, %State{symbol: symbol}}
  end

  @impl true
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(
        {:worker_report_step_succeed, %{symbol: symbol, worker_name: worker_name} = step_result},
        state
      ) do
    case Worker.Leader.worker_step_succeed(step_result) do
      :ignore ->
        :do_nothing

      :schedule_next_workflow ->
        # (TODO) Based on different symbol, we may want to reuse the worker context or want to use a fresh new worker.
        # Here, we just use fresh new worker.
        {:ok, _worker_pid} =
          Worker.Leader.terminate_worker(%{symbol: symbol, worker_name: worker_name})

        %{worker_name: new_worker_name} = Worker.Leader.add_new_worker(symbol)

        Worker.Leader.schedule_workflow_for_worker(%{
          symbol: symbol,
          worker_name: new_worker_name,
          schedule_method: :next_workflow
        })

        Worker.Leader.execute_workflow_for_worker(%{symbol: symbol, worker_name: new_worker_name})

      :execute_next_step ->
        Worker.Leader.execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:worker_report_step_crash, %{symbol: symbol, worker_name: worker_name} = step_result},
        state
      ) do
    case Worker.Leader.worker_step_failed(step_result) do
      :ignore ->
        :do_nothing

      :repaire_worker_and_retry_step ->
        # Useful for keep using one worker's context to test some step, like run different steps on terminal.
        Worker.Leader.repaire_worker_from_step_result(step_result)

        # schedule_workflow_for_worker will remove the current workflow from worker and execute a new one on it.
        # The worker still has the previous worker's context and state
        Worker.Leader.schedule_workflow_for_worker(%{
          symbol: symbol,
          worker_name: worker_name,
          schedule_method: :next_workflow
        })

        Worker.Leader.execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name})

      :repaire_worker_and_retry_step ->
        Worker.Leader.repaire_worker_from_step_result(step_result)
        Worker.Leader.execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name})

      # Compare with a step succeed: terminate worker, start a new worker.
      # Well, we don't need to terminate worker since it is crashed due to step failure.
      :skip_and_schedule_next_workflow ->
        nil

      unknow_schdule ->
        Logger.debug(
          "#{__MODULE__} received unknow schedule: #{unknow_schdule} for symbol: #{symbol}, worker_name: #{worker_name}"
        )

        Worker.Leader.execute_workflow_for_worker(%{symbol: symbol, worker_name: worker_name})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:update_from_worker,
         %{symbol: symbol, worker_name: worker_name, step_status: "succeed"}},
        state
      ) do
    Logger.debug(
      "#{symbol} -- update step succeed from worker: #{worker_name}, it is ready to continue to execute next step"
    )

    # trigger leader to execute next step for that worker
    {:ok, leader_pid} = Worker.Leader.get_leader_pid_from_symbol(symbol)
    GenServer.cast(leader_pid, {:execute_workflow_for_worker, worker_name})

    {:noreply, state}
  end

  @impl true
  def handle_cast(
        {:set_leader_state, %{leader_state: leader_state, reason: reason}},
        %{symbol: symbol} = state
      ) do
    Logger.warn("Save leader state for symbol: #{symbol}, due to: #{reason}")

    {:noreply, %{state | leader_backup: leader_state}}
  end

  def update_from_worker(%{symbol: symbol} = update_info) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:update_from_worker, update_info})
  end

  def get_collector_pid_for_symbol(symbol) do
    :"#{__MODULE__}_#{symbol}"
  end

  def state_for_symbol(symbol) do
    symbol
    |> get_collector_pid_for_symbol
    |> GenServer.call({:current_state})
  end

  def set_leader_state(%{symbol: symbol} = leader_state_info) do
    symbol
    |> get_collector_pid_for_symbol
    |> GenServer.cast({:set_leader_state, leader_state_info})
  end

  def report_step_for_symbol(symbol, {:worker_report_step_succeed, step_result}) do
    symbol
    |> get_collector_pid_for_symbol
    |> GenServer.cast({:worker_report_step_succeed, step_result})
  end

  def report_step_for_symbol(symbol, {:worker_report_step_crash, step_result}) do
    symbol
    |> get_collector_pid_for_symbol
    |> GenServer.cast({:worker_report_step_crash, step_result})
  end
end
