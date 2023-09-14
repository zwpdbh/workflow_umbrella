defmodule Workflow.PrepareTestData do
  def workflow_definition do
    [
      %{
        modulea: "module01",
        function: "function01"
      },
      %{
        module: "module02",
        function: "function01"
      },
      %{
        module: "module02",
        function: "function02"
      }
    ]
  end
end
