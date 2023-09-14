defmodule Workflow.PrepareTestData do
  def workflow_definition do
    [
      %{
        module: "module01",
        function: "function01",
        index: 0
      },
      %{
        module: "module02",
        function: "function01",
        index: 1
      },
      %{
        status: :todo,
        module: "module02",
        function: "function02",
        index: 2
      }
    ]
  end
end
