defmodule Steps.LogBackend do
  def log_to_file(%{log_file: log_file_path, content: content}) do
    Task.start(fn ->
      create_log_file_if_not_exist(log_file_path)

      {:ok, log_file} = File.open(log_file_path, [:append])
      write_content_to_log(content, log_file)

      IO.binwrite(log_file, "\n")
      File.close(log_file)
    end)
  end

  defp write_content_to_log(content, log_file) when is_map(content) do
    IO.binwrite(log_file, content |> Jason.encode!() |> Jason.Formatter.pretty_print())
    IO.binwrite(log_file, "{\n")

    content
    |> Enum.each(fn {key, value} ->
      IO.binwrite(log_file, "\t")
      IO.binwrite(log_file, "#{key}")
      IO.binwrite(log_file, " => ")

      case value do
        x when is_binary(x) ->
          IO.binwrite(log_file, x)

        _ ->
          IO.binwrite(log_file, "#{value}")
      end
    end)

    IO.binwrite("}\n")
  end

  defp write_content_to_log(content, log_file) when is_binary(content) do
    IO.binwrite(log_file, content)
  end

  defp write_content_to_log(content, log_file) do
    IO.binwrite(log_file, "#{inspect(content)}")
  end

  defp create_log_file_if_not_exist(log_file) do
    if not File.exists?(log_file) do
      File.mkdir_p!(Path.dirname(log_file))
    end
  end

  def create_tmp_log_file() do
    Path.join([File.cwd!(), "/tmp/logs", "#{Steps.Common.Time.get_time_millisecond()}.txt"])
  end

  def create_tmp_log_file(log_file_name) do
    Path.join([File.cwd!(), "/tmp/logs", log_file_name])
  end
end
