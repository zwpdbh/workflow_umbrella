defmodule Steps.LogBackend do
  alias Steps.Common.Time

  def log_to_file(%{log_file: log_file_path, content: content}) do
    Task.start(fn ->
      prepare_log_file_folder(log_file_path)

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

  defp prepare_log_file_folder(log_file) do
    log_file
    |> Path.dirname()
    |> create_folder_if_not_exist()
  end

  def create_folder_if_not_exist(folder) when is_binary(folder) do
    if not File.exists?(folder) do
      File.mkdir_p!(folder)
    end
  end

  def create_tmp_log_file() do
    Path.join([
      System.tmp_dir!(),
      "/logs",
      Time.get_current_date_str(),
      "#{Time.get_time_millisecond()}.txt"
    ])
  end

  def create_tmp_log_file(log_file_name) do
    Path.join([System.tmp_dir!(), "/logs", Time.get_current_date_str(), log_file_name])
  end
end
