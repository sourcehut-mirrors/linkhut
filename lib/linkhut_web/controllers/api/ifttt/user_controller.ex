defmodule LinkhutWeb.Api.IFTT.UserController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.Api.IFTT.UserView

  plug ExOauth2Provider.Plug.EnsureScopes, scopes: ~w(ifttt)

  def info(conn, _params) do
    user = conn.assigns[:current_user]

    conn
    |> render("info.json", user: user, url: Routes.user_url(conn, :show, user.username))
  end
end
