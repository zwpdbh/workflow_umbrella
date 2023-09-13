defmodule WorkflowWeb.ClusterLive do
  use WorkflowWeb, :live_view

  def mount(_params, _session, socket) do
    # socket = assign(socket, key: value)
    socket = assign(socket, clusters: [])
    {:ok, socket}
  end

  defmodule Index do
    use WorkflowWeb, :live_component

    def mount(_params, _session, socket) do
      # socket = assign(socket, clusters: [])
      {:ok, socket}
    end

    def render(assigns) do
      ~H"""
      <table>
        <tbody>
          <%= for cluster <- @clusters do %>
          <tr>
            <td><%= cluster.name %></td>
          </tr>
          <% end %>
        </tbody>
      </table>
      """
    end
  end
end
