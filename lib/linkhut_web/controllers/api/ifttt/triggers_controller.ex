defmodule LinkhutWeb.Api.IFTT.TriggersController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.Api.IFTT.TriggersView

  plug ExOauth2Provider.Plug.EnsureScopes, scopes: ~w(ifttt)

  alias Linkhut.Links

  def new_public_link(conn, params) do
    limit = Map.get(params, "limit", 50)
    user = conn.assigns[:current_user]
    links = Links.all(user, count: limit)

    conn
    |> render("new_public_link.json", links: links)
  end
end
