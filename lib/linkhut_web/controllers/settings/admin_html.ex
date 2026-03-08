defmodule LinkhutWeb.Settings.AdminHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.SettingsComponents

  embed_templates "admin_html/*"

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

  def moderation_dashboard(assigns) do
    ~H"""
    <section class="settings">
      <h4>Moderation</h4>
      <h5 :if={@banned_users != []}>Shadow Banned</h5>
      <.table :if={@banned_users != []} id="users" rows={@banned_users}>
        <:col :let={user} label="User">{user.username}</:col>
        <:col :let={%{moderation_entries: [ban | _]}} label="Banned On">{ban.inserted_at}</:col>
        <:col :let={%{moderation_entries: [ban | _]}} label="Reason">{ban.reason}</:col>
        <:action :let={user}>
          <.simple_form class="inline" for={%{}} action={~p"/_/admin/unban"}>
            <:actions>
              <.button name="username" value={user.username}>Unban</.button>
            </:actions>
          </.simple_form>
        </:action>
      </.table>
      <.simple_form :let={f} for={@form} as="ban" action={~p"/_/admin/ban"}>
        <.input field={f[:username]} label={gettext("User")} />
        <.input field={f[:reason]} label={gettext("Reason")} />
        <:actions>
          <.button type="submit" value="ban">Ban</.button>
        </:actions>
      </.simple_form>
    </section>
    """
  end
end
