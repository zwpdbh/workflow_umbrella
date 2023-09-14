defmodule Workflow.StepDefinition do
  use Ecto.Schema

  @required_fields [:module, :function]
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "steps_definition" do
    field(:module, :string)
    field(:function, :string)

    belongs_to :workflow_definition, Workflow.WorkflowDefinition 
  end

  def changeset(%__MODULE__{} = step_definition, %{} = attrs) do
    step_definition
    |> Ecto.Changeset.cast(attrs, @required_fields)
    |> Ecto.Changeset.validate_required(@required_fields)
  end
end
