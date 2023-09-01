defmodule Steps.Common.Time do
  def get_time_millisecond() do
    :os.system_time(:millisecond)
  end

  def get_timestamp() do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
  end

  def get_current_datetime(timezone \\ "Asia/Shanghai") do
    NaiveDateTime.utc_now()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone(timezone)
  end

  def get_current_date_str() do
    {:ok, dt} = Steps.Common.Time.get_current_datetime()
    "#{dt.year}-#{dt.month}-#{dt.day}"
  end

  def get_current_datetime_str(timezone \\ "Asia/Shanghai") do
    {:ok, dt} = Steps.Common.Time.get_current_datetime(timezone)
    "#{dt.year}-#{dt.month}-#{dt.day}_#{dt.hour}-#{dt.minute}-#{dt.second}"
  end
end
