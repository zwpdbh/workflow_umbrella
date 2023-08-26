defmodule Steps.Common.Time do
  def get_time_millisecond() do
    :os.system_time(:millisecond)
  end

  def get_timestamp() do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
  end
end
