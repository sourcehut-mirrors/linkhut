defmodule LinkhutWeb.Auth.SessionHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  def login(assigns) do
    ~H"""
    <div>
      <h3>Sign in</h3>
      <.form :let={f} for={@form} as={:session} action={~p"/_/login"}>
        <fieldset>
          <.input field={f[:username]} label={gettext("Username")} autocomplete="username" />
          <.input field={f[:password]} type="password" label={gettext("Password")} autocomplete="password" />
        </fieldset>
        <.button type="submit">Log In</.button>
      </.form>
      <div :if={not @logged_in?}>
        <p>
          <a class="doc" href={~p"/_/reset-password"}>{gettext("Forgot your password?")}</a>
        </p>
      </div>
    </div>
    """
  end
end
