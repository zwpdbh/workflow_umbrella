defmodule Workflow.StepDefinition do
  use Ecto.Schema

  @required_fields [:module_name, :function_name]
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "steps_definition" do
    field(:description, :string)
    field(:module_name, :string)
    field(:function_name, :string)

    belongs_to(:workflow_definition, Workflow.WorkflowDefinition)
  end

  def changeset(%__MODULE__{} = step_definition, %{} = attrs) do
    step_definition
    |> Ecto.Changeset.cast(attrs, @required_fields)
    |> Ecto.Changeset.validate_required(@required_fields)
  end

  def create_step_definition(%{} = attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:err, changeset.errors}
    end
  end
end
