defmodule LinkhutWeb.Settings.AdminHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  import LinkhutWeb.SettingsComponents

  embed_templates "admin_html/*"

  def moderation_dashboard(assigns) do
    ~H"""
    <section class="settings">
      <h4>Moderation</h4>
      <h5>Shadow Banned</h5>
      <.table id="users" rows={@banned_users}>
        <:col :let={user} label="User">{user.username}</:col>
        <:col :let={%{moderation_entries: [ban| _]}} label="Banned On">{ban.inserted_at}</:col>
        <:col :let={%{moderation_entries: [ban| _]}} label="Reason">{ban.reason}</:col>
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
        <.input field={f[:ban_reason]} label={gettext("Reason")} />
        <:actions>
          <.button type="submit" value="ban">Ban</.button>
        </:actions>
      </.simple_form>
    </section>
    """
  end
end
