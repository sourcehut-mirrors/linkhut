defmodule LinkhutWeb.Auth.SessionHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  def login(assigns) do
    ~H"""
    <div>
      <h3>Sign in</h3>
      <.form :let={f} for={@form} as={:session} action={~p"/_/login"}>
        <fieldset>
          <.input field={f[:username]} label={gettext("Username")} />
          <.input field={f[:password]} type="password" label={gettext("Password")} />
        </fieldset>
        <.button type="submit">Log In</.button>
      </.form>
    </div>
    """
  end
end
