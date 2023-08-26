defmodule Azure.Auth do
  alias Http.RestClient
  use GenServer

  # It is the resource identifier of the resource you want. It is affixed with the .default suffix.
  # Here, the resource identifier is checked by
  # Azure AD --> App Registration -> ScenarioFramework -> Overview. Then check "Application ID URI".
  @azure_scope "https://management.azure.com/.default"
  @azure_storage "https://storage.azure.com/.default"
  @xscnworkflowconsole_scope "https://microsoft.onmicrosoft.com/3b4ae08b-9919-4749-bb5b-7ed4ef15964d/.default"

  def azure_scope() do
    @azure_scope
  end

  def xscnworkflow_scope() do
    @xscnworkflowconsole_scope
  end

  def azure_storage() do
    @azure_storage
  end

  def scenario_deployment_api() do
    # When we use SP(service principal) to request access_token, we need to fill a scope.
    # For access_token used by web application xscenariodeploymentsapi, we check this scope by
    # Azure AD --> App Registration -> All applications (filter xscenariodeploymentsapi) -> Overview -> the value from "Application ID URI".
    "http://xscenariodeployments.cloudapp.net/" <> ".default"

    # In addition, we need to record down the: "Application (client) ID"  -- 242955bd-14cc-4a44-afba-873bfe978fcf
    # This will be used later.

    # How our SP could request such an access_token? What permissions/roles do we need?
    # This is defined by the "Scopes defined by this API" (by clicking "Application ID URI" or in the section "Expose an API" section of manage).
    # The settings "Define custom scopes to restrict access to data and functionality protected by the API."
    # Here, "the API" refers the API defined from "xscenariodeploymentsapi".
    # And currently there is only one scope for this API:

    # Scope: http://xscenariodeployments.cloudapp.net//user_impersonation
    # Who can consent: Admin and users.
    # It means anyone can grant it without admin requirement.

    # NOT NEEDED!
    # The below settings are not needed (I added there to remember how to define similar scope for app APIs)
    # To make our SP have access to the API defined by "xscenariodeploymentsapi", we need to
    # Azure AD --> App Registration --> "Owned applications" --> "zwpdbh" --> "Manage (section)" --> "API permissions" (click "+ Add a permission")
    # In "Select an API", select tab: "APIs my organization uses", fill the "242955bd-14cc-4a44-afba-873bfe978fcf" which is the "Application (client) ID"  when we check the overview from App Registration for "xscenariodeploymentsapi".
    # Select it and "Add permissions".
    # Now, our SP could request access_token for APIs defined by "xscenariodeploymentsapi".
  end

  defmodule AuthToken do
    defstruct [
      :expires_at,
      :access_token
    ]
  end

  defmodule ServicePrinciple do
    defstruct tenant_id: "",
              # The Application ID of zwpdbh (Enterprise Application)
              client_id: "",
              client_secret: ""

    def new() do
      %ServicePrinciple{
        tenant_id: "72f988bf-86f1-41af-91ab-2d7cd011db47",
        client_id: "2470ca86-3843-4aa2-95b8-97d3a912ff69",
        client_secret: read_secret()
      }
    end

    defp read_secret() do
      {:ok, secret} =
        (File.cwd!() <> "/" <> "client_secret.txt")
        |> File.read()

      secret
    end
  end

  defp get_access_token(%ServicePrinciple{} = sp, scope) do
    uri = "https://login.microsoftonline.com/#{sp.tenant_id}/oauth2/v2.0/token"

    headers = RestClient.add_header("Content-type", "application/x-www-form-urlencoded")

    query_parameters =
      RestClient.add_body("client_id", sp.client_id)
      |> RestClient.add_body("client_secret", sp.client_secret)
      |> RestClient.add_body("scope", scope)
      |> RestClient.add_body("grant_type", "client_credentials")

    case RestClient.post_request(uri, query_parameters, headers) do
      {:ok, %HTTPoison.Response{body: body_str, status_code: 200}} ->
        {:ok, decode_access_token_from_body(body_str), %{}}

      {_, error} ->
        {:error, %AuthToken{}, error}
    end
  end

  defp remaining_seconds(epxires_at) do
    DateTime.diff(epxires_at, DateTime.utc_now()) |> div(1000)
  end

  defp decode_access_token_from_body(body_str) when is_binary(body_str) do
    %{"access_token" => access_token, "expires_in" => expires_in} = Jason.decode!(body_str)

    %AuthToken{
      access_token: access_token,
      expires_at: DateTime.utc_now() |> DateTime.add(expires_in)
    }
  end

  @impl true
  def init(:ok) do
    # {:ok, %{sp: %ServicePrinciple{}, auth_map: %AuthToken{}}}
    {:ok, %{sp: ServicePrinciple.new(), auth_map: %{}}}
  end

  @impl true
  def handle_call({:get_new_access_token, scope}, _from, %{:sp => sp} = state) do
    {:ok, auth_token, _info} = get_access_token(sp, scope)

    {:reply, auth_token,
     put_in(state, Enum.map([:auth_map, scope], &Access.key(&1, %{})), auth_token)}
  end

  @impl true
  def handle_call(
        {:get_access_token, scope},
        _from,
        %{:sp => sp, :auth_map => auth_map} = state
      ) do
    {:ok, auth_token} =
      case auth_map[scope] do
        nil ->
          {:ok, auth_token, _info} = get_access_token(sp, scope)
          {:ok, auth_token}

        %AuthToken{access_token: _access_token, expires_at: expires_at} ->
          if remaining_seconds(expires_at) < 0 do
            {:ok, auth_token, _info} = get_access_token(sp, scope)
            {:ok, auth_token}
          else
            {:ok, auth_map[scope]}
          end
      end

    # IO.puts(auth_token)
    {:reply, auth_token,
     put_in(state, Enum.map([:auth_map, scope], &Access.key(&1, %{})), auth_token)}
  end

  # @impl true
  # def handle_call({:get_access_token}, _from, %{:auth_map => auth_map} = state) do
  #   {:reply, auth_map, state}
  # end
  @impl true
  def handle_call({:check_state}, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(msg, state) do
    require Logger
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Client API
  def start_link([]) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def get_new_auth_token(scope) do
    GenServer.call(__MODULE__, {:get_new_access_token, scope})
  end

  def get_auth_token(scope) do
    GenServer.call(__MODULE__, {:get_access_token, scope})
  end

  def check_state() do
    GenServer.call(__MODULE__, {:check_state})
  end
end
