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

  def az_delete_rg(context) do
    {:ok, _output} =
      %{
        cmd: "az group delete --name #{context.rg} --yes --no-wait",
        env: [{"AZURE_CONFIG_DIR", context.session_dir}]
      }
      |> Map.merge(context)
      |> Exec.run()

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

  # Step 5.1: Add node pool with 3 nodes
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
  # Configure Replication
  #########################################

  def config_acstor_replication(%{kubectl_config: kubectl_config} = context) do
    [
      "kubectl set image deployment/acstor-api-rest api-rest=azstortest.azurecr.io/artifact/424bd44c-13b4-4637-a5a4-0b9506e90413/buddy/rest:47c414cef91d05651985c66d6f3bbe317aab35e0-20230809.5 -n acstor",
      "kubectl set image deployment/acstor-agent-core agent-core=azstortest.azurecr.io/artifact/424bd44c-13b4-4637-a5a4-0b9506e90413/buddy/agents.core:47c414cef91d05651985c66d6f3bbe317aab35e0-20230809.5 -n acstor ",
      "kubectl set image deployment/acstor-csi-controller csi-controller=azstortest.azurecr.io/artifact/424bd44c-13b4-4637-a5a4-0b9506e90413/buddy/csi.controller:b7497942a0b4bfaa2f4467ff9132dbb24d110790-20230809.1 -n acstor",
      "kubectl set image daemonset/acstor-io-engine io-engine=azstortest.azurecr.io/artifact/424bd44c-13b4-4637-a5a4-0b9506e90413/buddy/mayastor-io-engine:6b2a0d7946981ffccefee65698c9f5cb57c19d62-20230801.1 -n acstor"
    ]
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
  # Create Storage Pool
  #########################################

  defp number_storage_pool(disk_type) do
    case disk_type do
      "nvme" -> 1
      "azure_disk" -> 3
      "san" -> 3
    end
  end

  def create_storage_pool(
        %{disk_type: disk_type, kubectl_config: kubectl_config, session_dir: session_dir} =
          context
      ) do
    num_storage_pool = number_storage_pool(disk_type)

    storage_pool_yaml_template =
      case disk_type do
        "nvme" ->
          ""

        "azure_disk" ->
          Path.join([
            File.cwd!(),
            "apps/workflow/lib/steps/acstor/storage_pool",
            "azure_disk.yml"
          ])

        "san" ->
          ""
      end

    storage_pool_settings =
      1..num_storage_pool
      |> Enum.to_list()
      |> Enum.map(fn index ->
        storage_pool_name = "storagepool#{index}"

        storage_pool_yaml =
          storage_pool_yaml_template
          |> File.read!()
          |> EEx.eval_string(
            %{storage_pool_name: storage_pool_name}
            |> Enum.into([], fn {k, v} -> {k, v} end)
          )

        storage_pool_yaml_file = Path.join([session_dir, "#{storage_pool_name}.yml"])

        Steps.LogBackend.log_to_file(
          %{log_file: storage_pool_yaml_file, content: storage_pool_yaml},
          :write
        )

        {storage_pool_name, storage_pool_yaml_file}
      end)

    yaml_files_for_each_storage_pool =
      storage_pool_settings |> Enum.map(fn {_, yaml_file} -> yaml_file end)

    storage_pools =
      storage_pool_settings |> Enum.map(fn {storage_pool_name, _} -> storage_pool_name end)

    yaml_files_for_each_storage_pool
    |> Enum.each(fn each_yaml ->
      {:ok, _output} =
        %{
          cmd: "kubectl apply -f  #{each_yaml}",
          env: [{"KUBECONFIG", kubectl_config}]
        }
        |> Map.merge(context)
        |> Exec.run()
    end)

    %{storage_pools: storage_pools}
  end

  #########################################
  # Create Storage Class
  #########################################
  def create_storage_class(%{kubectl_config: kubectl_config, session_dir: session_dir} = context) do
    storage_class_name = "acstor-replication"

    storage_pool_yaml =
      Path.join([
        File.cwd!(),
        "apps/workflow/lib/steps/acstor/storage_class",
        "class.yml"
      ])
      |> File.read!()
      |> EEx.eval_string(
        %{storage_class_name: storage_class_name}
        |> Enum.into([], fn {k, v} -> {k, v} end)
      )

    storage_class_yaml_file = Path.join([session_dir, "storage_class.yml"])

    Steps.LogBackend.log_to_file(
      %{log_file: storage_class_yaml_file, content: storage_pool_yaml},
      :write
    )

    {:ok, _output} =
      %{
        cmd: "kubectl apply -f  #{storage_class_yaml_file}",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{storage_class: storage_class_name}
  end

  #########################################
  # Create PVC
  #########################################

  def create_pvc(
        %{kubectl_config: kubectl_config, session_dir: session_dir, storage_class: storage_class} =
          context
      ) do
    pvc_name = get_random_pvc_name()
    pvc_size = get_random_pvc_size()

    pvc_yaml =
      Path.join([
        File.cwd!(),
        "apps/workflow/lib/steps/acstor/pvc",
        "pvc.yml"
      ])
      |> File.read!()
      |> EEx.eval_string(
        %{
          pvc_name: pvc_name,
          pvc_size: pvc_size,
          storage_class_name: storage_class
        }
        |> Enum.into([], fn {k, v} -> {k, v} end)
      )

    pvc_yaml_file = Path.join([session_dir, "#{pvc_name}.yml"])

    Steps.LogBackend.log_to_file(
      %{log_file: pvc_yaml_file, content: pvc_yaml},
      :write
    )

    {:ok, _output} =
      %{
        cmd: "kubectl apply -f  #{pvc_yaml_file}",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    case context do
      %{pvc_settings: existing_records} ->
        %{pvc_settings: [%{pvc_size: pvc_size, pvc_name: pvc_name} | existing_records]}

      _ ->
        %{pvc_settings: [%{pvc_size: pvc_size, pvc_name: pvc_name}]}
    end
  end

  defp get_random_pvc_size() do
    sizes = for n <- 100..1000, rem(n, 100) == 0, do: "#{n}Gi"
    sizes |> Enum.random()
  end

  defp get_random_pvc_name() do
    "pvc-#{get_random_str()}"
  end

  defp get_random_pod_name() do
    "pod-#{get_random_str()}"
  end

  #########################################
  # Create Pod
  #########################################

  def get_current_nodes(%{kubectl_config: kubectl_config} = context) do
    # get the node names related with "storagepool"
    {:ok, output} =
      %{
        cmd: "kubectl get nodes | grep storagepool",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    regex = ~r/aks-storagepool-\d+-vmss\d+/
    matches = Regex.scan(regex, output)

    nodes_name = Enum.map(matches, fn [match] -> String.trim(match) end)
    %{aks_nodes: nodes_name}
  end

  def label_nodes_with_labels(%{aks_nodes: aks_nodes, kubectl_config: kubectl_config} = context) do
    aks_node_label_registry =
      aks_nodes
      |> Enum.with_index()
      |> Enum.map(fn {node, i} ->
        %{node_name: node, selector: "targetNode", label: "node#{i}"}
      end)

    aks_node_label_registry
    |> Enum.each(fn %{node_name: node_name, label: label, selector: selector} ->
      {:ok, _output} =
        %{
          cmd: "kubectl label nodes #{node_name} #{selector}=#{label}",
          env: [{"KUBECONFIG", kubectl_config}]
        }
        |> Map.merge(context)
        |> Exec.run()
    end)

    %{aks_node_label_registry: aks_node_label_registry}
  end

  def check_labeled_noded(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get node --show-labels | grep targetNode",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  def create_pod_on_some_node(
        %{
          kubectl_config: kubectl_config,
          session_dir: session_dir
        } = context
      ) do
    available_node = get_available_node(context)

    if available_node == nil do
      raise "There is no available node to create, the current pod_node_registry is: #{inspect(context.pod_node_registry)} "
    end

    available_pvc = get_avaiable_pvc(context)

    if available_pvc == nil do
      raise "There is no available PVC to create pod, the current pod_pvc_registry is: #{inspect(context.pod_pvc_registry)}"
    end

    pod_name = get_random_pod_name()

    %{label: label} =
      context.aks_node_label_registry
      |> Enum.find(fn %{node_name: node_name} -> node_name == available_node end)

    pod_yaml =
      Path.join([
        File.cwd!(),
        "apps/workflow/lib/steps/acstor/pod",
        "pod.yml"
      ])
      |> File.read!()
      |> EEx.eval_string(
        %{pod_name: pod_name, node_label: label, pvc_name: available_pvc}
        |> Enum.into([], fn {k, v} -> {k, v} end)
      )

    pod_yaml_file = Path.join([session_dir, "#{pod_name}.yml"])

    Steps.LogBackend.log_to_file(
      %{log_file: pod_yaml_file, content: pod_yaml},
      :write
    )

    {:ok, _output} =
      %{
        cmd: "kubectl apply -f  #{pod_yaml_file}",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    case context do
      %{pod_node_registry: pod_node_registry, pod_pvc_registry: pod_pvc_registry} ->
        %{
          pod_pvc_registry: [%{pod_name: pod_name, pvc_name: available_pvc} | pod_pvc_registry],
          pod_node_registry: [
            %{pod_name: pod_name, node_name: available_node} | pod_node_registry
          ]
        }

      _ ->
        %{
          pod_pvc_registry: [%{pod_name: pod_name, pvc_name: available_pvc}],
          pod_node_registry: [%{pod_name: pod_name, node_name: available_node}]
        }
    end
  end

  defp get_available_node(%{aks_node_label_registry: aks_node_label_registry} = context) do
    case Map.get(context, :pod_node_registry) do
      # If there is no pod associated with pvc, we could select any of them
      nil ->
        %{node_name: node_name} =
          aks_node_label_registry
          |> Enum.random()

        node_name

      pod_node_registry ->
        nodes_in_use = pod_node_registry |> Enum.map(&Map.get(&1, :node_name))

        aks_node_label_registry
        |> Enum.map(&Map.get(&1, :node_name))
        |> Enum.reject(&(&1 in nodes_in_use))
        |> List.first()
    end
  end

  defp get_avaiable_pvc(%{pvc_settings: pvc_settings} = context) do
    case Map.get(context, :pod_pvc_registry) do
      # If there is no pod associated with pvc, we could select any of them
      nil ->
        %{pvc_name: pvc_name} = pvc_settings |> Enum.random()
        pvc_name

      pod_pvc_registry ->
        pvc_names_in_use = pod_pvc_registry |> Enum.map(&Map.get(&1, :pvc_name))

        pvc_settings
        |> Enum.map(&Map.get(&1, :pvc_name))
        |> Enum.reject(&(&1 in pvc_names_in_use))
        |> List.first()
    end
  end

  def kubectl_get_pods(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get pods -o wide",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  #########################################
  # Run fio
  #########################################

  def run_fio(%{pod_node_registry: pod_node_registry, kubectl_config: kubectl_config} = context) do
    %{pod_name: pod_name} = pod_node_registry |> Enum.random()

    fio_cmd = """
    kubectl exec -it #{pod_name} -- fio \
    --name=benchtest --size=2g \
    --filename=/volume/test \
    --direct=1 --rw=randrw --rwmixread=30 \
    --ioengine=libaio --bs=4k --iodepth=8 \
    --numjobs=1 --time_based \
    --runtime=60 \
    --verify_backlog=4096 \
    --serialize_overlap=1 \
    --do_verify=1 \
    --verify=crc32 --group_reporting
    """

    {:ok, _output} =
      %{
        cmd: fio_cmd,
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  def get_acstor_api_value(%{kubectl_config: kubectl_config} = context) do
    {:ok, output} =
      %{
        cmd: "kubectl get pod -n acstor | grep api-rest",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{"acstor_api" => acstor_api} = Regex.named_captures(~r/(?<acstor_api>[a-zA-z0-9-]*)/, output)

    %{acstor_api_value: acstor_api}
  end

  def small_sleep(_context) do
    Process.sleep(5_000)
    %{}
  end

  def big_sleep(_context) do
    Process.sleep(10 * 5_000)
    %{}
  end

  def forward_acstor_api_pod_to_host(
        %{kubectl_config: kubectl_config, acstor_api_value: acstor_api_value} = context
      ) do
    host_port = 9092

    Task.start(fn ->
      %{
        cmd: "lsof -i :#{host_port} | awk 'NR!=1 {print $2}' | xargs kill"
      }
      |> Map.merge(context)
      |> Exec.run()

      {:ok, _output} =
        %{
          cmd: "kubectl port-forward #{acstor_api_value} -n acstor #{host_port}:8081 &",
          env: [{"KUBECONFIG", kubectl_config}]
        }
        |> Map.merge(context)
        |> Exec.run()
    end)

    %{acstor_api_host_port: host_port}
  end

  def get_replication_info(
        %{
          acstor_api_host_port: host_port
        } = context
      ) do
    {:ok, cmd_output} =
      %{
        cmd: "curl 'http://127.0.0.1:#{host_port}/v0/volumes?max_entries=1'"
      }
      |> Map.merge(context)
      |> Exec.run()

    %{"info" => info} = Regex.named_captures(~r/(?<info>{.*})/, cmd_output)

    case info do
      nil ->
        raise "failed to get json info, the output is: #{cmd_output}"

      json_output ->
        %{replication_info: Jason.decode!(json_output)}
    end
  end

  def get_xfs_disk_pools_used_by_pod(
        %{replication_info: info, pod_node_registry: pod_node_registry} = _context
      ) do
    node_xfs_disk_pool_registry =
      info
      |> Map.get("entries")
      |> List.first()
      |> Map.get("state")
      |> Map.get("replica_topology")
      |> Enum.map(fn {_id, %{"pool" => pool, "node" => node}} ->
        %{"pool" => pool, "node" => node}
      end)

    nodes_in_use = pod_node_registry |> Enum.map(&Map.get(&1, :node_name))

    xfs_disk_pools_used_by_pod =
      node_xfs_disk_pool_registry
      |> Enum.filter(fn %{"node" => node_name} -> Enum.member?(nodes_in_use, node_name) end)
      |> Enum.map(fn %{"pool" => pool} -> pool end)

    %{xfs_disk_pools_used_by_pod: xfs_disk_pools_used_by_pod}
  end

  def check_the_replication(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get pod -n acstor | grep io-engine ",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  def list_the_io_engine_pods(%{kubectl_config: kubectl_config} = context) do
    {:ok, _output} =
      %{
        cmd: "kubectl get pods -n acstor | grep io-engine ",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    %{}
  end

  # TODO use the xfs_disk_pools_used_by_pod and io engine pods to run md5
  # Also need to find the mapping of acstor-io-engine-4949p where it comes from
  def run_mdf_xfs_disk_pools_used_by_pod(
        %{
          kubectl_config: kubectl_config,
          xfs_disk_pools_used_by_pod: _xfs_disk_pools_used_by_pod,
          replication_info: replication_info,
          symbol: symbol
        } = context
      ) do
    node_pool_topology =
      replication_info
      |> Map.get("entries")
      |> List.first()
      |> Map.get("state")
      |> Map.get("replica_topology")
      |> Enum.map(fn {_id, %{"pool" => pool, "node" => node}} ->
        %{"pool" => pool, "node" => node}
      end)

    diskes_to_verify =
      node_pool_topology
      |> Enum.reduce([], fn %{"pool" => pool_name}, acc ->
        disk_path = Path.join(["xfs-disk-pool", pool_name])

        result =
          %{
            cmd: "kubectl exec acstor-io-engine-4949p -n acstor -c io-engine -- ls #{disk_path}",
            env: [{"KUBECONFIG", kubectl_config}]
          }
          |> Map.merge(context)
          |> Exec.run()

        case result do
          {:err, _output} ->
            acc

          {:ok, output} ->
            regex =
              ~r/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/

            diskes =
              Regex.scan(regex, output)
              |> Enum.map(fn [x] -> x end)
              |> Enum.map(fn each_disk -> Path.join([disk_path, each_disk]) end)

            diskes ++ acc
        end
      end)

    Task.Supervisor.async_stream_nolink(
      SymbolSupervisor.get_task_supervisor(symbol),
      diskes_to_verify,
      fn disk_path ->
        %{
          cmd:
            "kubectl exec acstor-io-engine-4949p -n acstor -c io-engine -- md5sum  #{disk_path}",
          env: [{"KUBECONFIG", kubectl_config}]
        }
        |> Map.merge(context)
        |> Exec.run()
      end,
      max_concurrency: 1,
      timeout: 5_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true
    )
    |> Enum.reduce([], fn result, acc ->
      [result | acc]
    end)
    |> IO.inspect(label: "#{__MODULE__} 908")

    %{}
  end

  #########################################
  # Rebuild
  #########################################

  # We need to unable the node which there is no user pod created on it.
  # For instance, the fio application is created on node0, we should NOT unlable this node.
  # For rebuilding work, the minimum labeled node must be >= 2.
  # Delete pod with label "io-engine" by unlabelling it.
  def unlabel_not_used_node(%{kubectl_config: kubectl_config} = context) do
    node_not_in_use = find_node_not_in_use(context)

    {:ok, _output} =
      %{
        cmd: "kubectl label node #{node_not_in_use} acstor.azure.com/io-engine-",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    # case context do
    #   %{unlabelled_nodes: nodes} -> %{unlabelled_nodes: [node_not_in_use | nodes]}
    #   _ -> %{unlabelled_nodes: [node_not_in_use]}
    # end

    %{}
  end

  defp find_node_not_in_use(
         %{aks_nodes: aks_nodes, pod_node_registry: pod_node_registry} = _context
       ) do
    node_names_in_registry =
      pod_node_registry
      |> Enum.map(&Map.get(&1, :node_name))
      |> Enum.uniq()

    Enum.find(aks_nodes, fn node_name ->
      node_name not in node_names_in_registry
    end)
  end

  defp num_replicas(replication_info) do
    replication_info
    |> Map.get("entries")
    |> List.first()
    |> Map.get("spec")
    |> Map.get("num_replicas")
  end

  def verify_unlabel_result(
        %{kubectl_config: kubectl_config, replication_info: replication_info} = context
      ) do
    replica_num = num_replicas(replication_info)

    {:ok, output} =
      %{
        cmd: "kubectl get node --show-labels | grep io-engine | wc -l",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    if not (replica_num - 1) == output |> String.trim() |> String.to_integer() do
      raise "after unlabel, the number of node with acstor label is not decreased"
    end

    {:ok, output} =
      %{
        cmd: "kubectl get pod -n acstor | grep io-engine | wc -l",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    if not (replica_num - 1) == output |> String.trim() |> String.to_integer() do
      raise "after unlabel, the number of pod is not decreased"
    end

    %{}
  end

  def label_node_back_with_acstor(
        %{kubectl_config: kubectl_config, replication_info: replication_info} = context
      ) do
    node_not_in_use = find_node_not_in_use(context)
    replica_num = num_replicas(replication_info)

    {:ok, _output} =
      %{
        cmd: "kubectl label node #{node_not_in_use} acstor.azure.com/io-engine=acstor",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    Process.sleep(5_000)
    # Verify labelled result
    {:ok, output} =
      %{
        cmd: "kubectl get node --show-labels | grep io-engine | wc -l",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    if not (replica_num == output |> String.trim() |> String.to_integer()) do
      raise "number of nodes with acstor label is not equal the number of replicas: #{replica_num}"
    end

    {:ok, output} =
      %{
        cmd: "kubectl get pod -n acstor | grep io-engine | wc -l",
        env: [{"KUBECONFIG", kubectl_config}]
      }
      |> Map.merge(context)
      |> Exec.run()

    if not (replica_num == output |> String.trim() |> String.to_integer()) do
      raise "number of pod is not equal the number of replicas: #{replica_num}"
    end

    %{}
  end

  def verify_rebuilding_state(context) do
    forward_acstor_api_pod_to_host(context) |> IO.inspect(label: "#{__MODULE__} 1024")
    Process.sleep(5_000)
    %{replication_info: updated_info} = get_replication_info(context)

    nodes_not_online =
      updated_info
      |> Map.get("entries")
      |> List.first()
      |> Map.get("state")
      |> Map.get("replica_topology")
      |> Enum.reject(fn {_id, %{"state" => state}} -> state == "Online" end)

    case nodes_not_online do
      [] ->
        %{replication_info: updated_info}

      others ->
        raise "Not all nodes are online: #{inspect(others)}"
    end
  end

  #########################################
  # For testing only
  #########################################
  def dummy_step_will_fail(%{} = _context) do
    Process.sleep(10_000)

    {:ok, _output} =
      Exec.run(%{
        cmd: "ls non_exist_file"
      })

    %{}
  end

  def test_kubectl_cmd(%{kubectl_config: kubectl_config} = context, cmd) do
    %{
      cmd: cmd,
      env: [{"KUBECONFIG", kubectl_config}]
    }
    |> Map.merge(context)
    |> Exec.run()

    %{}
  end

  def test_az_cmd(%{session_dir: session_dir} = context, cmd) do
    %{
      cmd: cmd,
      env: [{"AZURE_CONFIG_DIR", session_dir}]
    }
    |> Map.merge(context)
    |> Exec.run()

    %{}
  end
end
