defmodule Steps.Exec do
  require Logger

  @moduledoc """
  For execute shell command from elixir
  """
  alias Steps.LogBackend

  # When running command with special context
  def run(%{cmd: cmd_str, log_file: log_file, env: env_settings}) when is_list(env_settings) do
    run_aux(%{cmd: cmd_str, log_file: log_file, env: env_settings})
  end

  def run(%{cmd: cmd_str, env: env_settings}) when is_list(env_settings) do
    log_file = Steps.LogBackend.create_tmp_log_file()
    run_aux(%{cmd: cmd_str, log_file: log_file, env: env_settings})
  end

  # When user specified a log file
  def run(%{cmd: cmd_str, log_file: log_file}) do
    run_aux(%{cmd: cmd_str, log_file: log_file, env: nil})
  end

  # When user doesn't specify log file
  def run(%{cmd: cmd_str}) do
    # use another interface function to run cmd
    run(cmd_str)
  end

  # When user doesn't specify log file
  def run(cmd_str) when is_binary(cmd_str) do
    log_file = Steps.LogBackend.create_tmp_log_file()
    run_aux(%{cmd: cmd_str, log_file: log_file, env: nil})
  end

  # Helper function to run cmd from shell
  # Append shell command and its result into a local log file
  # And return the output
  defp run_aux(%{cmd: cmd_str, log_file: log_file, env: env_settings}) do
    Logger.info("#{cmd_str}")

    timestamp_str = LogBackend.generate_local_timestamp()

    # also record the command we executed into log file
    Steps.LogBackend.log_to_file(%{
      log_file: log_file,
      content: "#{timestamp_str} $#{cmd_str}"
    })

    {output, status} =
      case env_settings do
        nil ->
          System.cmd(
            "bash",
            ["-c", cmd_str],
            stderr_to_stdout: true
          )

        settings ->
          System.cmd(
            "bash",
            ["-c", cmd_str],
            stderr_to_stdout: true,
            env: settings
          )
      end

    Logger.info("#{output}")
    Steps.LogBackend.log_to_file(%{log_file: log_file, content: output})

    case status do
      0 -> {:ok, output}
      _err_code -> {:err, output}
    end
  end
end
