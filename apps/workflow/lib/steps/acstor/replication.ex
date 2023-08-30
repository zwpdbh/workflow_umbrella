defmodule Steps.Acstor.Replication do
  @moduledoc """
  Steps for testing ACStor Replication
  """
  require Logger
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
  def az_set_subscription(context) do
    {:ok, _output} =
      %{
        cmd: "az account set --subscription #{context.sub}",
        env: [{"AZURE_CONFIG_DIR", context.session_dir}]
      }
      |> Map.merge(context)
      |> Exec.run()

    # {:ok, _output} =
    #   Exec.run(%{
    #     cmd: "az account set --subscription #{sub_id}",
    #     log_file: log_file,
    #     env: [{"AZURE_CONFIG_DIR", session_dir}]
    #   })

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
      %{
        cmd: "az group create  --location #{region} --name #{rg}",
        log_file: log_file,
        env: [{"AZURE_CONFIG_DIR", session_dir}]
      }
      |> Exec.run()

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

  # Step 5.0 set disk type
  def set_disk_type_to_azure_disk(%{} = _context) do
    %{
      disk_type: "azure_disk"
    }
  end

  def set_disk_type_to_nvme(%{} = _context) do
    %{
      disk_type: "nvme"
    }
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
        env: [{"AZURE_CONFIG_DIR", session_dir}],
        log_file: log_file
      })

    %{vm_sku: vm_sku}
  end

  # Step 6. Get AKS config for running kubectl later
  def get_aks_config(%{log_file: log_file, aks: aks, session_dir: session_dir} = context) do
    timestamp_str = Steps.LogBackend.generate_local_timestamp()
    Logger.info("#{timestamp_str} -- set kubectl context for aks: #{aks}")

    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} -- set kubectl context for aks: #{aks}"
    })

    # Save kubectl context to file for later use
    kubectl_config_value = Azure.Aks.get_aks_config(context)
    kubectl_config_file = Path.join([session_dir, "kubectl_config"])

    Steps.LogBackend.log_to_file(%{log_file: kubectl_config_file, content: kubectl_config_value})

    %{kubectl_config: kubectl_config_file}
  end

  # Step 7: Helper function to check nodes
  def kubectl_get_nodes(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get nodes -o wide",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  # Step 8. Label the node
  def kubectl_label_nodes(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd:
          "kubectl label nodes --selector agentpool=storagepool acstor.azure.com/io-engine=acstor",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  # Step 9. Show node labels
  def kubectl_show_nodes_label(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get nodes --show-labels",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  # Step 10.1
  def az_check_managed_id(context) do
    {:ok, output} =
      %{
        cmd:
          "az aks show -g #{context.rg} -n #{context.aks} --out tsv --query identityProfile.kubeletidentity.objectId",
        env: [{"AZURE_CONFIG_DIR", context.session_dir}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{managed_id: output |> String.trim()}
  end

  # Step 10.2
  def az_check_node_resource_group(context) do
    {:ok, output} =
      %{
        cmd: "az aks show -g #{context.rg} -n #{context.aks} --out tsv --query nodeResourceGroup",
        env: [{"AZURE_CONFIG_DIR", context.session_dir}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{node_rg: output |> String.trim()}
  end

  # Step 10.3
  # 创建了一个custom role 解决了， 创建custom role的时候 需要赋予什么权限可以根据报错信息： 'Microsoft.Authorization/roleAssignments/write'
  # scope could be whole subscription.
  def az_assign_contributor_role(context) do
    {:ok, _output} =
      %{
        cmd:
          "az role assignment create --assignee #{context.managed_id} --role Contributor --scope /subscriptions/#{context.sub}/resourceGroups/#{context.node_rg}",
        env: [{"AZURE_CONFIG_DIR", context.session_dir}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  #########################################
  # Install ACStor Addons
  #########################################

  def install_acstor_addons(
        %{session_dir: session_dir, kubectl_config: kubectl_config, log_file: log_file} = context
      ) do
    git_repo = "git@ssh.dev.azure.com:v3/msazure/One/azstor-add-ons"
    download_folder = Path.join([session_dir, "azstor_addons"])

    timestamp_str = Steps.LogBackend.generate_local_timestamp()
    Logger.info("#{timestamp_str} -- Install acstor Addons from git repo: #{git_repo}")

    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} -- Install acstor Addons from git repo: #{git_repo}"
    })

    cmd_01 = "git clone git@ssh.dev.azure.com:v3/msazure/One/azstor-add-ons #{download_folder}"

    cmd_02 = """
    cd #{download_folder}/charts/latest/ &&
    helm dependency build
    """

    cmd_03 = """
    cd #{download_folder} &&
    helm install acstor charts/latest --namespace acstor --create-namespace \
    --version 0.0.0-latest \
    --set image.tag=latest \
    --set image.registry="azstortest.azurecr.io" \
    --set image.repo="mayadata" \
    --set capacityProvisioner.image.tag=latest \
    --set capacityProvisioner.image.registry="azstortest.azurecr.io"
    """

    cmd_04 = "kubectl get pods -n acstor"

    [cmd_01, cmd_02, cmd_03, cmd_04]
    |> Enum.each(fn each_cmd ->
      {:ok, _output} =
        %{
          cmd: each_cmd,
          env: [{"KUBECONFIG", kubectl_config}]
        }
        |> Map.merge(context)
        |> Exec.run()
    end)

    %{}
  end

  #########################################
  #
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
