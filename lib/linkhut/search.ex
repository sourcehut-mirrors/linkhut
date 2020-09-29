defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Links.Link
  alias Linkhut.Search.Context

  def search(context, query, params \\ [])

  def search(context, "", _params) do
    links_for_context(context)
    |> preload([_, u], user: u)
    |> order_by(desc: :inserted_at)
  end

  def search(context, query, _params) do
    links_for_context(context)
    |> where([l, _], fragment("? @@ phraseto_tsquery(?)", l.search_vector, ^query))
    |> preload([_, u], user: u)
    |> order_by(desc: :inserted_at)
  end

  def links_for_context(%Context{from: from, tagged_with: tags, visible_as: visible_as}) do
    Link
    |> join(:inner, [l], u in assoc(l, :user))
    |> from_user(from)
    |> tagged_with(tags)
    |> visible_as(visible_as)
  end

  defp from_user(query, user) when is_nil(user), do: query

  defp from_user(query, user) do
    query
    |> where([_, u], u.username == ^user)
  end

  defp tagged_with(query, tags) when is_nil(tags) or tags == [], do: query

  defp tagged_with(query, tags) do
    query
    |> where(
      [l, _],
      fragment("? @> string_to_array(?, ',')::varchar[]", l.tags, ^Enum.join(tags, ","))
    )
  end

  defp visible_as(query, user) when is_nil(user) do
    query
    |> where(is_private: false)
  end

  defp visible_as(query, user) do
    query
    |> where([l, u], l.is_private == false or u.username == ^user)
  end
end
