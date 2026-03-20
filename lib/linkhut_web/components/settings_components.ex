defmodule LinkhutWeb.SettingsComponents do
  @moduledoc """
  Provides UI components for Settings pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.NavigationComponents, only: [nav_link: 1]

  defdelegate format_bytes(bytes), to: Linkhut.Formatting
  defdelegate crawler_display_name(type), to: Linkhut.Formatting
  defdelegate format_display_name(format), to: Linkhut.Formatting

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
              {~p"/_/preferences", gettext("Preferences")},
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

  def state_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>State</th>
          <th>Count</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={{state, count} <- @rows}>
          <td>{state}</td>
          <td>{count}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :rows, :list, required: true

  def queue_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>Queue</th>
          <th>State</th>
          <th>Count</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <td>{row.queue}</td>
          <td>{row.state}</td>
          <td>{row.count}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc "Grouped breakdown of snapshots: by type, then by state within each type."
  attr :groups, :list, required: true

  def snapshot_breakdown_table(assigns) do
    rows =
      Enum.flat_map(assigns.groups, fn group ->
        header = {:header, group.format, group.total_count, group.total_size}

        states =
          Enum.map(group.states, fn {state, count, size} -> {:state, state, count, size} end)

        [header | states]
      end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <table>
      <thead>
        <tr>
          <th>Format / State</th>
          <th>Count</th>
          <th>Size</th>
        </tr>
      </thead>
      <tbody>
        <%= for row <- @rows do %>
          <%= case row do %>
            <% {:header, format, count, size} -> %>
              <tr class="group-header">
                <td><strong>{format_display_name(format)}</strong></td>
                <td><strong>{count}</strong></td>
                <td><strong>{format_bytes(size)}</strong></td>
              </tr>
            <% {:state, state, count, size} -> %>
              <tr>
                <td style="padding-left: 1.5em;">{state}</td>
                <td>{count}</td>
                <td>{format_bytes(size)}</td>
              </tr>
          <% end %>
        <% end %>
      </tbody>
    </table>
    """
  end
end
