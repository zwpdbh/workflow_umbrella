defmodule Workflow do
  @moduledoc """
  Workflow keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  require Logger

  def test do
    Playground.hello()
  end

  def start_scenario(symbol) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        DynamicSymbolSupervisor,
        {SymbolSupervisor, symbol}
      )
  end

  def stop_scenario(symbol) do
    scenario_sup_pid = Process.whereis(:"Elixir.SymbolSupervisor_#{symbol}")

    if scenario_sup_pid != nil do
      DynamicSupervisor.terminate_child(DynamicSymbolSupervisor, scenario_sup_pid)
    else
      {:err, "process Elixir.SymbolSupervisor-#{symbol} not exist"}
    end
  end
end
