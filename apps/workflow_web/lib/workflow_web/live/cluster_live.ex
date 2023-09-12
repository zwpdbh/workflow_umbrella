defmodule WorkflowWeb.Live.ClusterLive do
  use WorkflowWeb, :live_view

  defmodule Index do
    def mount(_params, _session, socket) do
      # socket = assign(socket, key: value)
      {:ok, socket}
    end
  end
end
