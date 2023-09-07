defmodule Azure.Aks do
  alias Azure.Auth
  alias Azure.Auth.AuthToken
  alias Http.RestClient

  def get_aks_config(%{sub: sub_id, rg: rg_name, aks: aks_name}) do
    # Need to get the Aks configuration from created cluster
    %AuthToken{expires_at: _, access_token: access_token} =
      Auth.get_auth_token(Auth.azure_scope())

    headers =
      RestClient.add_header("Content-type", "application/json")
      |> RestClient.add_header("Authorization", "Bearer #{access_token}")

    query_options = RestClient.add_query("api-version", "2023-01-01")

    # POST https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ContainerService/managedClusters/{resourceName}/listClusterAdminCredential
    url =
      "https://management.azure.com/subscriptions/#{sub_id}/resourceGroups/#{rg_name}/providers/Microsoft.ContainerService/managedClusters/#{aks_name}/listClusterAdminCredential"

    {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} =
      RestClient.post_request(url, %{}, headers, query_options)

    response_body
    |> Jason.decode!()
    |> Map.get("kubeconfigs")
    |> List.first()
    |> Map.get("value")
    |> Base.decode64!()
  end
end
