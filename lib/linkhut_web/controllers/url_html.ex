defmodule LinkhutWeb.UrlHTML do
  @moduledoc """
  View helpers for the URL detail page.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.Helpers
  import LinkhutWeb.Controllers.Utils
  import LinkhutWeb.LinkComponents

  embed_templates "url_html/*"

  defp format_period(%DateTime{} = dt, :month) do
    Calendar.strftime(dt, "%b %Y")
  end

  defp format_period(%DateTime{} = dt, :week) do
    week_end = DateTime.add(dt, 6, :day)

    # Typographic convention: tight en-dash for same-month ranges (Mar 5–11, 2026),
    # spaced en-dash when months differ (Mar 25 – Apr 3, 2026).
    if dt.month == week_end.month do
      Calendar.strftime(dt, "%b %-d") <> "–" <> Calendar.strftime(week_end, "%-d, %Y")
    else
      Calendar.strftime(dt, "%b %-d") <> " – " <> Calendar.strftime(week_end, "%b %-d, %Y")
    end
  end

  defp format_period(%DateTime{} = dt, :day) do
    Calendar.strftime(dt, "%b %-d, %Y")
  end

  defp format_period(%DateTime{} = dt, :hour) do
    Calendar.strftime(dt, "%b %-d, %-H:%M")
  end

  defp chart_params(buckets) do
    max_count = buckets |> Enum.map(& &1.count) |> Enum.max(fn -> 1 end)
    bar_count = length(buckets)
    chart_width = 600
    chart_height = 24

    %{
      max_count: max_count,
      chart_width: chart_width,
      chart_height: chart_height,
      bar_width: chart_width / bar_count,
      min_bar_height: 2,
      border_height: 1
    }
  end
end
