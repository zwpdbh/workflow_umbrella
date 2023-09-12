defmodule WorkflowWeb.ClusterLive do
  use WorkflowWeb, :live_view

  def mount(_params, _session, socket) do
    # socket = assign(socket, key: value)
    {:ok, socket}
  end

  defmodule Index do
    use WorkflowWeb, :live_component

    def init(context) do
      context
    end
  end
end
