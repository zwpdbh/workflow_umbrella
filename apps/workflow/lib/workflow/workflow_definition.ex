defmodule Workflow.WorkflowDefinition do
  use Ecto.Schema

  @required_fields [:name]

  schema "workflow_definitions" do
    field(:name, :string)
    field(:description, :string)

    has_many(:workflow_steps, Workflow.StepDefinition)
  end

  def changeset(%__MODULE__{} = step_definition, %{} = attrs) do
    step_definition
    |> Ecto.Changeset.cast(attrs, @required_fields)
    |> Ecto.Changeset.validate_required(@required_fields)
  end
end
