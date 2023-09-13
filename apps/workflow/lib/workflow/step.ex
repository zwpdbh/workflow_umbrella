defmodule Workflow.Step do
  # By defining a schema, Ecto automatically defines a struct with the schema fields:
  use Ecto.Schema

  @required_fields [:status, :module, :function, :retried]

  schema "steps" do
    field(:index, :integer)

    field(:status, Ecto.Enum,
      values: [:todo, :in_progress, :succeed, :failed, :canceled],
      default: :todo
    )

    field(:module, :string)
    field(:function, :string)
    field(:retried, :integer)
  end

  @spec new(map()) :: {:ok, %Workflow.Step{}} | {:error, map()}
  def new(attrs) do
    changeset =
      %Workflow.Step{}
      |> Ecto.Changeset.cast(attrs, @required_fields)

    if changeset.valid? do
      {:ok, changeset.data}
    else
      {:error, changeset.errors}
    end
  end
end
