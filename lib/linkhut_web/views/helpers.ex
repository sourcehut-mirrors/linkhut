defmodule LinkhutWeb.Helpers do
  @moduledoc false

  require LinkhutWeb.Gettext
  alias Timex

  @doc """
  Makes dates pretty
  """
  def prettify(time1, time2 \\ Timex.now()) do
    diff = Timex.diff(time2, time1, :days)

    cond do
      diff < 0 ->
        Timex.format!(time1, "{relative}", :relative)

      diff < 1 ->
        LinkhutWeb.Gettext.gettext("Today")

      diff <= 2 ->
        LinkhutWeb.Gettext.gettext("Yesterday")

      diff < 10 ->
        Timex.format!(time1, "{relative}", :relative)

      true ->
        Timex.format!(time1, "{0D} {Mshort} {0YY}")
    end
  end
end
