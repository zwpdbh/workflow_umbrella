defmodule Worker.Monitor do
  use GenServer

  require Logger

  @moduledoc """
  This module is used to monitor the state changes of Worker.Leader.
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
    Logger.info("Initializing Worker.Monitor for symbol: #{symbol}")
    {:ok, %State{symbol: symbol}}
  end

  @impl true
  def handle_call({:current_state}, _from, state) do
    {:reply, state, state}
  end

  # Callback for handling step error
  @impl true
  def handle_cast(
        {:update_from_worker,
         %{
           symbol: symbol,
           worker_name: worker_name,
           step_status: "error",
           which_module: which_module,
           which_function: which_function,
           step_output: step_output
         }},
        state
      ) do
    Logger.debug(
      "#{symbol} -- update step error from worker: #{worker_name}, #{which_module}.#{which_function}, output: #{step_output}"
    )

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

  def get_monitor_pid_for_symbol(symbol) do
    :"#{__MODULE__}_#{symbol}"
  end

  def state_for_symbol(symbol) do
    symbol
    |> get_monitor_pid_for_symbol
    |> GenServer.call({:current_state})
  end

  def set_leader_state(%{symbol: symbol} = leader_state_info) do
    symbol
    |> get_monitor_pid_for_symbol
    |> GenServer.cast({:set_leader_state, leader_state_info})
  end
end
