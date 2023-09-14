defmodule Workflow.Repo.Migrations.Init do
  use Ecto.Migration

  def change do
    create table("workflow_definitions") do
      add(:name, :string)
      add(:description, :string)

      timestamps()
    end

    create table("step_definitions") do
      add(:name, :string)
      add(:description, :string)
      add(:workflow_definition_id, references("workflow_definitions"))

      timestamps()
    end
  end
end
