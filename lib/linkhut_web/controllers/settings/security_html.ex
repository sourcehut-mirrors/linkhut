defmodule LinkhutWeb.Settings.SecurityHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.SettingsComponents

  def security(assigns) do
    ~H"""
    <.menu is_admin?={Linkhut.Accounts.is_admin?(@current_user)} request_path={@conn.request_path} />
    <div>
      <section class="settings">
        <h4>Change your password</h4>
        <p>
          A link to complete the process will be sent to the email on file for your account ({@email}).
        </p>
        <.form :let={f} for={@form} as={:user} action={~p"/_/reset-password"} class="inline">
          <.input type="hidden" field={f[:email]} />
          <.button type="submit">Send reset link</.button>
        </.form>
      </section>
    </div>
    """
  end
end
