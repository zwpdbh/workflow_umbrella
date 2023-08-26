defmodule Steps.Acstor.Replication do
  @moduledoc """
  Steps for testing ACStor Replication
  """
  alias Steps.Exec

  def set_subscription(%{sub: sub_id}) do
    Exec.run("az account set --subscription #{sub_id}")
  end
end
