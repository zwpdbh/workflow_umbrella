defmodule Workflow.WorkflowDefintionTest do
  use Workflow.DataCase
  alias Workflow.PrepareTestData

  setup do
    :ok
  end

  test "There are 3 workflow steps" do
    workflow_steps =
      PrepareTestData.workflow_definition()
      |> Enum.map(fn each -> Workflow.StepDefinition.create_step_definition(each) end)
      |> Enum.map(fn each -> Ecto.Changeset.apply_changes(each) end)

    n = PrepareTestData.workflow_definition() |> length
    assert n == 2
  end
end
