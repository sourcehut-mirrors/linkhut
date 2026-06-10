defmodule LinkhutWeb.Settings.StatsHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.SettingsComponents
  import Linkhut.Formatting, only: [format_bytes: 1]

  embed_templates "stats_html/*"
end
