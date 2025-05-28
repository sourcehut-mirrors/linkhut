defmodule LinkhutWeb.Api.TagsController do
  use LinkhutWeb, :controller

  plug ExOauth2Provider.Plug.EnsureScopes,
       [scopes: ~w(tags:write)] when action in [:delete, :rename]

  plug ExOauth2Provider.Plug.EnsureScopes, [scopes: ~w(tags:read)] when action in [:get]

  alias Linkhut.Tags

  def get(conn, _) do
    user = conn.assigns[:current_user]

    conn
    |> render(:get, %{tags: Tags.all(user)})
  end

  def delete(conn, %{"tag" => tag}) when is_binary(tag) do
    user = conn.assigns[:current_user]
    Tags.delete(user, tag)

    render(conn, :done)
  end

  def rename(conn, %{"old" => old, "new" => new}) when is_binary(old) and is_binary(new) do
    user = conn.assigns[:current_user]
    Tags.rename(user, old: old, new: new)

    render(conn, :done)
  end
end
