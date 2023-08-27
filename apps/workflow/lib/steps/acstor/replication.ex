defmodule Steps.Acstor.Replication do
  @moduledoc """
  Steps for testing ACStor Replication
  """
  alias Steps.Exec
  alias Steps.Common.Time

  def init_context() do
    %{
      sub: "65490f91-f2c2-4514-80ba-4ec1de89aeda",
      region: "eastus",
      rg: "acstor-replication-test"
    }
  end

  # Step 1
  def az_login_using_sp(%{} = _settings) do
    {:ok, session_dir} =
      Azure.Auth.ServicePrinciple.new()
      |> create_cli_session()

    # If the step produce any extra parameters, we need to add return it as eplicitly in map form.
    %{session_dir: session_dir}
  end

  defp create_cli_session(%Azure.Auth.ServicePrinciple{
         tenant_id: tenant_id,
         client_id: client_id,
         client_secret: client_secret
       }) do
    {:ok, session_dir} = prepare_session_folder()

    {:ok, _output} =
      Exec.run(%{
        cmd:
          "az login --service-principal -u #{client_id} -p #{client_secret} --tenant #{tenant_id}",
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    {:ok, session_dir}
  end

  defp prepare_session_folder() do
    path =
      Path.join([
        System.tmp_dir!(),
        "/logs",
        Time.get_current_date_str(),
        "az_cli_sessions",
        get_random_str()
      ])

    Steps.LogBackend.create_folder_if_not_exist(path)
    {:ok, path}
  end

  defp get_random_str() do
    "abcdefghijklmnopqrstuvwxyz0123456789"
    |> String.graphemes()
    |> Enum.take_random(6)
    |> Enum.join("")
  end

  # Step 2
  def az_set_subscription(%{sub: sub_id, session_dir: session_dir}) do
    {:ok, _output} =
      Exec.run(%{
        cmd: "az account set --subscription #{sub_id}",
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    # If the step produce no extra parameter (or context), we need to return empty map
    %{}
  end
end
