defmodule Steps.Acstor.Replication do
  @moduledoc """
  Steps for testing ACStor Replication
  """
  alias Steps.Exec
  alias Steps.Common.Time

  def init_context() do
    random_suffix = "#{get_random_str()}"

    {:ok, session_dir} = prepare_session_folder(random_suffix)
    log_file = Path.join([session_dir, "log.txt"])

    %{
      sub: "d20d4862-d44e-429d-bcd7-fe71a331a8b8",
      region: "eastus",
      suffix: random_suffix,
      prefix: "acstorbyzhaowei",
      session_dir: session_dir,
      log_file: log_file
    }
  end

  defp prepare_session_folder(random_suffix) do
    path =
      Path.join([
        System.tmp_dir!(),
        "/logs",
        Time.get_current_datetime_str(),
        random_suffix
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

  defp create_cli_session(
         %Azure.Auth.ServicePrinciple{
           tenant_id: tenant_id,
           client_id: client_id,
           client_secret: client_secret
         },
         %{session_dir: session_dir, log_file: log_file}
       ) do
    {:ok, _output} =
      Exec.run(%{
        cmd:
          "az login --service-principal -u #{client_id} -p #{client_secret} --tenant #{tenant_id}",
        log_file: log_file,
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    {:ok, session_dir}
  end

  # Step 1: az login
  def az_login_using_sp(%{session_dir: session_dir, log_file: log_file} = _settings) do
    {:ok, session_dir} =
      Azure.Auth.ServicePrinciple.new()
      |> create_cli_session(%{session_dir: session_dir, log_file: log_file})

    # If the step produce any extra parameters, we need to add return it as eplicitly in map form.
    %{session_dir: session_dir}
  end

  # Step 2: set subscription
  def az_set_subscription(%{sub: sub_id, session_dir: session_dir, log_file: log_file}) do
    {:ok, _output} =
      Exec.run(%{
        cmd: "az account set --subscription #{sub_id}",
        log_file: log_file,
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    # If the step produce no extra parameter (or context), we need to return empty map
    %{}
  end

  # Step 3: create resource group
  def az_create_resource_group(%{
        prefix: common_prefix,
        suffix: random_suffix,
        region: region,
        session_dir: session_dir,
        log_file: log_file
      }) do
    rg = "#{common_prefix}-#{random_suffix}"

    {:ok, _output} =
      Exec.run(%{
        cmd: "az group create  --location #{region} --name #{rg}",
        log_file: log_file,
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    %{rg: rg}
  end

  # Step 4: create aks cluster
  def az_create_aks_cluster(%{
        rg: rg,
        session_dir: session_dir,
        log_file: log_file
      }) do
    {:ok, _output} =
      Exec.run(%{
        cmd:
          "az aks create -n #{rg} -g #{rg} --generate-ssh-keys --attach-acr /subscriptions/d64ddb0c-7399-4529-a2b6-037b33265372/resourceGroups/azstor-test-rg/providers/Microsoft.ContainerRegistry/registries/azstortest",
        log_file: log_file,
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      })

    %{aks: rg}
  end

  # Step 5: Add node pool
  def az_add_node_pool(%{
        aks: aks,
        rg: rg,
        disk_type: disk_type,
        session_dir: session_dir,
        log_file: log_file
      }) do
    # Add node pool with 3 nodes
    vm_sku =
      case disk_type do
        "azure_disk" -> "Standard_D4s_v3"
        "nvme" -> "Standard_L8s_v3"
      end

    {:ok, _output} =
      Exec.run(%{
        cmd:
          "az aks nodepool add --cluster-name #{aks} --name storagepool --resource-group #{rg} --node-vm-size #{vm_sku} --node-count 3 ",
        session_dir: session_dir,
        log_file: log_file
      })

    %{vm_sku: vm_sku}
  end

  # Step 6. Get AKS config for running kubectl later
  def get_aks_config(%{log_file: log_file, aks: aks} = context) do
    timestamp_str = Steps.LogBackend.generate_local_timestamp()

    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} -- set kubectl context for aks: #{aks}"
    })

    kubectl_config = Azure.Aks.get_aks_config(context)
    %{kubectl_config: kubectl_config}
  end

  # For testing only to test how to handle a step failed
  def dummy_step_will_fail(%{} = _context) do
    Process.sleep(10_000)

    {:ok, _output} =
      Exec.run(%{
        cmd: "ls non_exist_file"
      })

    %{}
  end
end
