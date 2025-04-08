defmodule LinkhutWeb.Auth.RegistrationHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  def register(assigns) do
    ~H"""
    <div>
      <h3>Registration</h3>
      <.form :let={f} for={@changeset} as={:user} action={~p"/_/register"}>
        <fieldset>
          <.input field={f[:username]} label={gettext("Username")} />
          <.inputs_for :let={cf} field={f[:credential]}>
            <.input field={cf[:email]} label={gettext("Email")} />
            <.input field={cf[:password]} type="password" label={gettext("Password")} />
          </.inputs_for>
        </fieldset>
        <.button type="submit">Register</.button>
      </.form>
    </div>
    """
  end
end
