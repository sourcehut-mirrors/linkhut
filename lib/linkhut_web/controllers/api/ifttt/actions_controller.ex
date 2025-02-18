defmodule LinkhutWeb.Api.IFTTT.ActionsController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.Api.IFTTT.ActionsView

  plug ExOauth2Provider.Plug.EnsureScopes,
    scopes: ~w(ifttt),
    handler: LinkhutWeb.Plugs.AuthErrorHandler

  alias Linkhut.Links
  alias LinkhutWeb.ErrorHelpers

  def add_public_link(conn, %{"actionFields" => %{"url" => url} = params}) do
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    if link != nil do
      update_link(conn, link, params)
    else
      create_link(conn, params)
    end
  end

  def add_public_link(_conn, _params) do
    raise LinkhutWeb.Api.IFTTT.Errors.BadRequestError, "missing parameters"
  end

  def add_private_link(conn, %{"actionFields" => %{"url" => url} = params}) do
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    params = Map.put(params, "is_private", true)

    if link != nil do
      update_link(conn, link, params)
    else
      create_link(conn, params)
    end
  end

  def add_private_link(_conn, _params) do
    raise LinkhutWeb.Api.IFTTT.Errors.BadRequestError, "missing parameters"
  end

  defp update_link(conn, link, params) do
    user = conn.assigns[:current_user]

    case Links.update_link(link, params) do
      {:ok, link} ->
        conn
        |> render("success.json",
          id: link.url,
          url: Routes.user_bookmark_url(conn, :show, user.username, link.url)
        )

      {:error, changeset} ->
        raise LinkhutWeb.Api.IFTTT.Errors.BadRequestError,
              Ecto.Changeset.traverse_errors(changeset, &ErrorHelpers.translate_error/1)
    end
  end

  defp create_link(conn, params) do
    user = conn.assigns[:current_user]
    params = Map.update(params, "tags", "via:ifttt", fn tags -> tags <> " via:ifttt" end)

    case Links.create_link(user, params) do
      {:ok, link} ->
        conn
        |> render("success.json",
          id: link.url,
          url: Routes.user_bookmark_url(conn, :show, user.username, link.url)
        )

      {:error, changeset} ->
        raise LinkhutWeb.Api.IFTTT.Errors.BadRequestError,
              Ecto.Changeset.traverse_errors(changeset, &ErrorHelpers.translate_error/1)
    end
  end
end
