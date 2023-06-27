defmodule Workflow.Repo do
  use Ecto.Repo,
    otp_app: :workflow,
    adapter: Ecto.Adapters.Postgres
end
