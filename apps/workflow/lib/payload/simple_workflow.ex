defmodule Payload.SimpleWorkflow do
  alias Payload.SimpleSteps

  def generate_workflow() do
    Payload.SimpleSteps.module_info()
  end

  def random_workflow_from_simple_steps() do
    SimpleSteps.module_info()
    |> Keyword.get(:exports)
    |> Enum.filter(fn {k, _v} -> k != :__info__ and k != :module_info end)
    |> Enum.map(fn {k, _v} ->
      {"Elixir.Payload.SimpleSteps", Atom.to_string(k)}
    end)
    |> Enum.shuffle()
  end
end
