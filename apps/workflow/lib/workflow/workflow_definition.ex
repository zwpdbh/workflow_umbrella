defmodule Workflow.WorkflowDefinition do
  use Ecto.Schema
  alias Workflow.StepDefinition
  alias Workflow.Repo

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

  def convert_steps(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {each, index} ->
      case StepDefinition.create_step_definition(each) do
        {:ok, step_definition} -> step_definition
        {:err, errors} -> raise "step #{index} has error: #{inspect(errors)}"
      end
    end)
  end

  def create_workflow_definition_with_steps(steps, attrs \\ %{}) do
    valid_steps = convert_steps(steps)

    Repo.transaction(fn ->
      workflow_definition_changeset =
        %__MODULE__{}
        |> changeset(attrs)
        |> Ecto.Changeset.put_embed(:workflow_steps, valid_steps)

      case Repo.insert(workflow_definition_changeset) do
        {:ok, workflow_definition} ->
          {:ok, workflow_definition}

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end
end
