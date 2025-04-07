defmodule LinkhutWeb.Settings.ProfileHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  import LinkhutWeb.ErrorHelpers

  def profile(assigns) do
    ~H"""
    {LinkhutWeb.SettingsView."profile.html"(assigns)}
    """
  end

  def delete_account(assigns) do
    ~H"""
    {LinkhutWeb.SettingsView."_menu.html"(assigns)}
    <div>
      <section class="settings">
        <h4>Delete Account</h4>
        <.form :let={f} for={@changeset} as={:delete_form} action={~p"/_/profile/delete"}>
          <fieldset>
            <.input field={f[:confirmed]} type="checkbox" label={gettext("I acknowledge that I want to permanently delete my account and all data associated with it")} />
            {error_tag(f, :applications)}
          </fieldset>
          <.button type="submit">Permanently delete account</.button>
        </.form>
      </section>
    </div>
    """
  end
end
