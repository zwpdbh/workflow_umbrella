defmodule Steps.Exec do
  require Logger

  @moduledoc """
  For execute shell command from elixir
  """

  # When user specified a log file
  def run(%{cmd: cmd_str, log_file: log_file}) do
    run_aux(%{cmd: cmd_str, log_file: log_file})
  end

  # When user doesn't specify log file
  def run(%{cmd: cmd_str}) do
    # use another interface function to run cmd
    run(cmd_str)
  end

  # When user doesn't specify log file
  def run(cmd_str) when is_binary(cmd_str) do
    log_file = Steps.LogBackend.create_tmp_log_file()
    run_aux(%{cmd: cmd_str, log_file: log_file})
  end

  # Helper function to run cmd from shell
  # Append shell command and its result into a local log file
  # And return the output
  defp run_aux(%{cmd: cmd_str, log_file: log_file}) do
    Steps.LogBackend.log_to_file(%{log_file: log_file, content: "$#{cmd_str}"})

    {output, status} = System.cmd("bash", ["-c", cmd_str], stderr_to_stdout: true)
    Steps.LogBackend.log_to_file(%{log_file: log_file, content: output})

    case status do
      0 -> {:ok, output}
      _err_code -> {:err, output}
    end
  end
end
