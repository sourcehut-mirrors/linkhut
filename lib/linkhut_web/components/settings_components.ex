defmodule LinkhutWeb.SettingsComponents do
  @moduledoc """
  Provides UI components for Settings pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.NavigationComponents, only: [nav_link: 1]

  attr :is_admin?, :boolean, required: true, doc: "flag for whether to show admin tabs"
  attr :request_path, :string, required: true, doc: "the current path"

  def menu(assigns) do
    ~H"""
    <div class="navigation">
      <h2 class="navigation-header">Settings</h2>
      <ul class="navigation-tabs">
        <.nav_link
          :for={
            {to, name} <- [
              {~p"/_/profile", gettext("Profile")},
              {~p"/_/security", gettext("Security")},
              {~p"/_/import", gettext("Import / Export")},
              {~p"/_/misc", gettext("Misc")},
              {~p"/_/oauth", gettext("OAuth")},
              @is_admin? && {~p"/_/admin", gettext("Admin")}
            ]
          }
          request_path={@request_path}
          to={to}
          name={name}
        />
      </ul>
    </div>
    <hr />
    """
  end
end
