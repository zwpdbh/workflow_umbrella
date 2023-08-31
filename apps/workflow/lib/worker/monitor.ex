defmodule Worker.Monitor do
  use GenServer

  require Logger

  @moduledoc """
  This module is used to monitor the state changes of Worker.Leader.
  We trigger extra event to leader.
  """

  defmodule State do
    defstruct symbol: nil
  end

  def start_link(symbol) do
    GenServer.start_link(__MODULE__, symbol, name: :"#{__MODULE__}_#{symbol}")
  end

  @impl true
  def init(symbol) do
    {:ok, %State{symbol: symbol}}
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

    {:noreply, state}
  end

  def update_from_worker(%{symbol: symbol} = update_info) do
    GenServer.cast(:"#{__MODULE__}_#{symbol}", {:update_from_worker, update_info})
  end
end
