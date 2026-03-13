defmodule LinkhutWeb.Settings.PreferencesHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.SettingsComponents

  alias Linkhut.Accounts.Preferences

  embed_templates "preferences_html/*"

  defp timezone_options, do: Preferences.timezone_options()
end
