defmodule Workflow.Step do
  # By defining a schema, Ecto automatically defines a struct with the schema fields:
  use Ecto.Schema

  @required_fields [:status, :module, :function, :retried, :index]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "steps" do
    field(:index, :integer)

    field(:status, Ecto.Enum,
      values: [:todo, :in_progress, :succeed, :failed, :canceled],
      default: :todo
    )

    field(:module, :string)
    field(:function, :string)
    field(:retried, :integer, default: 0)
  end

  @spec new(map()) :: {:ok, %Workflow.Step{}} | {:error, map()}
  def new(attrs) do
    result = changeset(%__MODULE__{}, attrs)

    if result.valid? do
      {:ok, struct(%__MODULE__{}, attrs)}
    else
      {:error, result.errors}
    end
  end

  def changeset(%__MODULE__{} = step_instance, %{} = attrs) do
    step_instance
    |> Ecto.Changeset.cast(attrs, @required_fields)
    |> Ecto.Changeset.validate_required(@required_fields)
  end
end
