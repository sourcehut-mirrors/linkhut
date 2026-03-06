defmodule LinkhutWeb.Api.IFTTT.UserController do
  use LinkhutWeb, :controller

  plug :put_view, json: LinkhutWeb.Api.IFTTT.UserJSON

  plug ExOauth2Provider.Plug.EnsureScopes,
    scopes: ~w(ifttt),
    handler: LinkhutWeb.Plugs.AuthErrorHandler

  def info(conn, _params) do
    user = conn.assigns[:current_user]

    render(conn, :info, user: user, url: Routes.user_url(conn, :show, user.username))
  end
end
