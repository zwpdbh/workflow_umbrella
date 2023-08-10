defmodule Workflow do
  @moduledoc """
  Workflow keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

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
end
