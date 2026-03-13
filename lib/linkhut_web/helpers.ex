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
    date = datetime |> in_timezone(timezone) |> to_date()
    today = timezone |> today()
    diff = Date.diff(today, date)

    cond do
      diff < 0 ->
        time_ago(diff * -86_400)

      diff < 1 ->
        gettext("Today")

      diff < 2 ->
        gettext("Yesterday")

      diff < 10 ->
        time_ago(diff * 86_400)

      true ->
        Calendar.strftime(date, "%d %b %y")
    end
  end

  @doc """
  Formats a duration in seconds as a human-readable relative time string.

  Accepts either a `DateTime` (computes diff from now) or an integer
  number of seconds.
  """
  def time_ago(%DateTime{} = dt) do
    DateTime.diff(DateTime.utc_now(), dt) |> time_ago()
  end

  def time_ago(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)
    months = div(days, 30)
    years = div(days, 365)

    cond do
      seconds < 5 ->
        gettext("just now")

      seconds < 46 ->
        ngettext("1 second ago", "%{count} seconds ago", seconds, count: seconds)

      minutes < 60 ->
        minutes = max(minutes, 1)
        ngettext("1 minute ago", "%{count} minutes ago", minutes, count: minutes)

      hours < 24 ->
        ngettext("1 hour ago", "%{count} hours ago", hours, count: hours)

      days < 30 ->
        ngettext("1 day ago", "%{count} days ago", days, count: days)

      months < 12 ->
        ngettext("1 month ago", "%{count} months ago", months, count: months)

      true ->
        years = max(years, 1)
        ngettext("1 year ago", "%{count} years ago", years, count: years)
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
    case DateTime.shift_zone(dt, timezone) do
      {:ok, converted} -> converted
      _ -> dt
    end
  end

  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)
  defp to_date(%Date{} = d), do: d

  defp today(nil), do: Date.utc_today()

  defp today(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} -> DateTime.to_date(dt)
      _ -> Date.utc_today()
    end
  end
end
