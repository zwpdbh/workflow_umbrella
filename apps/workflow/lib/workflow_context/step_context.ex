defmodule WorkflowContext.StepContext do
  # import Ecto.Query

  alias Workflow.{
    Step
  }

  def create_step(params) do
    Step.changeset(%Step{}, params)
  end
end
