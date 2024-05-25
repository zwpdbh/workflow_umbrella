defmodule Workflow.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Workflow.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Workflow.PubSub},
      # Start Finch
      {Finch, name: Workflow.Finch},
      # Start a worker by calling: Workflow.Worker.start_link(arg)
      # {Workflow.Worker, arg}
      {
        DynamicSupervisor,
        strategy: :one_for_one, name: DynamicSymbolSupervisor
      }
      # Azure.Auth
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: WorkflowApp.Supervisor)
  end
end
