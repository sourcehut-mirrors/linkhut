defmodule LinkhutWeb.SettingsComponents do
  @moduledoc """
  Provides UI components for Settings pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.NavigationComponents, only: [nav_link: 1]

  defdelegate format_bytes(bytes), to: Linkhut.Formatting
  defdelegate crawler_display_name(type), to: Linkhut.Formatting

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
              {~p"/_/stats", gettext("Stats")},
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

  attr :rows, :list, required: true

  def snapshot_type_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>Type</th>
          <th>Count</th>
          <th>Size</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td>{crawler_display_name(row.type)}</td>
          <td>{row.count}</td>
          <td>{format_bytes(row.size)}</td>
        </tr>
      </tbody>
    </table>
    """
  end
end
