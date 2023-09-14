defmodule Workflow.WorkflowDefintionTest do
  use Workflow.DataCase
  alias Workflow.PrepareTestData

  setup do
    :ok
  end

  test "There are 3 workflow steps" do
    n = PrepareTestData.workflow_definition() |> length
    assert n == 2
  end
end
