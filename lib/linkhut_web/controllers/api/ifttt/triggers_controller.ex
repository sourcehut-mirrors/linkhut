defmodule LinkhutWeb.Api.IFTTT.TriggersController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.Api.IFTTT.TriggersView

  plug ExOauth2Provider.Plug.EnsureScopes,
    scopes: ~w(ifttt),
    handler: LinkhutWeb.Plugs.AuthErrorHandler

  alias Linkhut.Links

  def new_public_link(conn, params) do
    limit = Map.get(params, "limit", 50)
    user = conn.assigns[:current_user]
    links = Links.all(user, count: limit, is_private: false, is_unread: false)

    conn
    |> render("links.json", links: links)
  end

  def new_public_link_tagged(conn, %{"triggerFields" => %{"tag" => tag}} = params)
      when is_binary(tag) and tag != "" do
    limit = Map.get(params, "limit", 50)
    user = conn.assigns[:current_user]
    links = Links.all(user, count: limit, is_private: false, is_unread: false, tags: [tag])

    conn
    |> render("links.json", links: links)
  end

  def new_public_link_tagged(_conn, _params) do
    raise LinkhutWeb.Api.IFTTT.Errors.BadRequestError, "missing parameters"
  end
end
