defmodule LinkhutWeb.Api.IFTTController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.Api.IFTTView

  plug ExOauth2Provider.Plug.EnsureScopes,
       [scopes: ~w(posts:read)] when action in [:user_info]

  def user_info(conn, _params) do
    user = conn.assigns[:current_user]

    conn
    |> render(:user_info,
         name: user.username,
         id: "#{user.id}",
         url: Routes.user_url(conn, :show, user.username)
       )
  end
end
