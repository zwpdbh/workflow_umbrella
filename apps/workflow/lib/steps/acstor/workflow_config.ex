defmodule Steps.Acstor.WorkflowConfig do
  @moduledoc """
  Based on some configuration to generate different kind of workflows
  """

  def step_may_fail(_context) do
    # n = Enum.random(0..7)
    # Process.sleep(n * 1_000)

    # if n > 5 do
    #   raise "time out"
    # end

    Process.sleep(1_000)
    raise "time out"

    %{}
  end

  def dummy_workflow() do
    1..5
    |> Enum.to_list()
    |> Enum.map(fn _ ->
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"}
    end)
  end

  def azure_disk_replication() do
    [
      "az_login_using_sp",
      "az_set_subscription",
      "az_create_resource_group",
      "az_create_aks_cluster",
      "set_disk_type_to_azure_disk",
      "az_add_node_pool",
      "get_aks_config",
      "kubectl_get_nodes",
      "kubectl_label_nodes",
      "kubectl_show_nodes_label",
      "az_check_managed_id",
      "az_check_node_resource_group",
      "az_assign_contributor_role",
      "install_acstor_addons",
      "config_acstor_replication",
      "create_storage_pool",
      "create_storage_class",
      "create_pvc",
      "get_current_nodes",
      "label_nodes_with_labels",
      "check_labeled_noded",
      "create_pod_on_some_node",
      "kubectl_get_pods",
      "run_fio",
      "get_acstor_api_value",
      "small_sleep",
      "forward_acstor_api_pod_to_host",
      "get_replication_info",
      "get_xfs_disk_pools_used_by_pod",
      "check_the_replication",
      "list_the_io_engine_pods",
      "run_mdf_xfs_disk_pools_used_by_pod",
      "unlabel_not_used_node",
      "verify_unlabel_result",
      "big_sleep",
      "label_node_back_with_acstor",
      "big_sleep",
      "verify_rebuilding_state",
      "az_delete_rg"
    ]
  end
end
