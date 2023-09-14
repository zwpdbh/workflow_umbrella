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

  # Create a list of  Workflow.Step by converting raw workflow_defintion which is list of steps (map).
  def convert_steps(steps) when is_list(steps) do
    steps
    |> Enum.with_index()
    |> Enum.map(fn {each, index} ->
      case StepDefinition.create_step_definition(each) do
        {:ok, step_definition} -> step_definition
        {:err, errors} -> raise "step #{index} has error: #{inspect(errors)}"
      end
    end)
  end

  # Create Workflow.WorkflowDefinition
  def create_workflow_definition_with_steps(steps, attrs \\ %{}) do
    workflow_definition_changeset =
      %__MODULE__{}
      |> changeset(attrs)
      |> Ecto.Changeset.put_assoc(:workflow_steps, steps)

    if workflow_definition_changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(workflow_definition_changeset)}
    else
      {:err, workflow_definition_changeset.errors}
    end
  end

  def insert_workflow_definition(workflow_definition) do
    Repo.transaction(fn ->
      case Repo.insert(workflow_definition) do
        {:ok, workflow_definition} ->
          {:ok, workflow_definition}

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  def play(steps, attrs \\ %{}) do
    {:ok, workflow_definition} = create_workflow_definition_with_steps(steps, attrs)

    insert_workflow_definition(workflow_definition)
  end
end
