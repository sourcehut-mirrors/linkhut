defmodule LinkhutWeb.Helpers do
  @moduledoc false

  require LinkhutWeb.Gettext
  alias Timex

  @doc """
  Makes dates pretty
  """
  def prettify(time1, time2 \\ Timex.today()) do
    time1 = Timex.to_date(time1)
    time2 = Timex.to_date(time2)
    diff = Date.diff(time2, time1)

    cond do
      diff < 0 ->
        Timex.format!(time1, "{relative}", :relative)

      diff < 1 ->
        LinkhutWeb.Gettext.gettext("Today")

      diff < 2 ->
        LinkhutWeb.Gettext.gettext("Yesterday")

      diff < 10 ->
        Timex.format!(time1, "{relative}", :relative)

      true ->
        Timex.format!(time1, "{0D} {Mshort} {0YY}")
    end
  end
end
