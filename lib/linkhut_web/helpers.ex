defmodule LinkhutWeb.Helpers do
  @moduledoc false

  use Gettext, backend: LinkhutWeb.Gettext

  @doc """
  Formats a datetime for display, choosing the most natural representation
  based on age: "Today", "Yesterday", relative for recent dates, then
  an absolute date for older ones.

  An optional timezone string shifts the display for absolute dates.
  """
  def format_date(datetime, timezone \\ nil) do
    date = datetime |> in_timezone(timezone) |> Timex.to_date()
    today = timezone |> today()
    diff = Date.diff(today, date)

    cond do
      diff < 0 ->
        Timex.format!(date, "{relative}", :relative)

      diff < 1 ->
        gettext("Today")

      diff < 2 ->
        gettext("Yesterday")

      diff < 10 ->
        Timex.format!(date, "{relative}", :relative)

      true ->
        Calendar.strftime(date, "%d %b %y")
    end
  end

  @doc """
  Converts a datetime to the given timezone. Returns the input unchanged
  when timezone is nil or conversion fails.
  """
  def in_timezone(dt, nil), do: dt

  def in_timezone(%NaiveDateTime{} = dt, timezone) do
    dt
    |> DateTime.from_naive!("Etc/UTC")
    |> in_timezone(timezone)
  end

  def in_timezone(%DateTime{} = dt, timezone) do
    case Timex.Timezone.convert(dt, timezone) do
      %DateTime{} = converted -> converted
      _ -> dt
    end
  end

  defp today(nil), do: Date.utc_today()

  defp today(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end
end
