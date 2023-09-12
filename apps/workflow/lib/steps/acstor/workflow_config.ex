defmodule Steps.Acstor.WorkflowConfig do
  @moduledoc """
  Based on some configuration to generate different kind of workflows
  """

  def step_may_fail(%{log_file: log_file} = _context) do
    timestamp_str = Steps.LogBackend.generate_local_timestamp()

    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} -- execute step_may_fail"
    })

    n = Enum.random(0..7)
    Process.sleep(n * 100)

    if n > 3 do
      raise "time out"
    end

    %{}
  end

  def step_may_fail_and_retry(%{log_file: log_file} = _context) do
    timestamp_str = Steps.LogBackend.generate_local_timestamp()

    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} -- execute step_may_fail_and_retry"
    })

    n = Enum.random(0..7)
    Process.sleep(n * 100)

    if n > 3 do
      raise "time out"
    end

    %{}
  end

  def dummy_workflow_for_testing_retry() do
    [
      {"Steps.Acstor.WorkflowConfig", "step_may_fail_and_retry"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail_and_retry"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail_and_retry"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"}
    ]
  end

  def dummy_workflow_for_testing_skip_failed() do
    [
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"},
      {"Steps.Acstor.WorkflowConfig", "step_may_fail"}
    ]
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

  def nvme_replication() do
    [
      "az_login_using_sp",
      "az_set_subscription",
      "az_create_resource_group",
      "az_create_aks_cluster",
      "set_disk_type_to_nvme",
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

  def retry_policy(function_name) do
    retry? =
      (["kubectl", "and_retry"] ++ azure_disk_replication())
      |> Enum.any?(fn x -> String.contains?(function_name, x) end)

    # if we find some function_name should retry, we specify its maximum retry count
    if retry? do
      2
    else
      0
    end
  end
end
