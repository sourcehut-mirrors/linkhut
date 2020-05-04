defmodule LinkhutWeb.LinkView do
  use LinkhutWeb, :view

  use Timex

  alias Timex.Duration

  @doc """
  Makes dates pretty
  """
  def prettify(date) do
    days_ago =
      Duration.diff(Duration.now(), Duration.from_days(Date.diff(date, ~D[1970-01-01])), :days)

    cond do
      days_ago < 1 ->
        "Today"

      days_ago == 1 ->
        LinkhutWeb.Gettext.gettext("Yesterday")

      days_ago < 10 ->
        Timex.format!(date, "{relative}", :relative)

      true ->
        Timex.format!(date, "{0D} {Mshort} {0YY}")
    end
  end
end
