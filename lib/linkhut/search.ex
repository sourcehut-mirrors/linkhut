defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Links
  alias Linkhut.Search.Context

  def search(context, query, params \\ [])

  def search(context, "", _params) do
    links_for_context(context)
    |> preload([_, _, u], user: u)
    |> order_by(desc: :inserted_at)
  end

  def search(context, query, _params) do
    links_for_context(context)
    |> Map.merge(%{score: 0})
    |> where([l, _, _], fragment("? @@ phraseto_tsquery(?)", l.search_vector, ^query))
    |> preload([_, _, u], user: u)
    |> order_by(desc: :inserted_at)
  end

  def links_for_context(%Context{from: from, tagged_with: tags, visible_as: visible_as}) do
    Links.links()
    |> join(:inner, [l, _], u in assoc(l, :user))
    |> from_user(from)
    |> tagged_with(tags)
    |> visible_as(visible_as)
  end

  defp from_user(query, user) when is_nil(user), do: query

  defp from_user(query, user) do
    query
    |> where([_, _, u], u.id == ^user.id)
  end

  defp tagged_with(query, tags) when is_nil(tags) or tags == [], do: query

  defp tagged_with(query, tags) do
    query
    |> where(
      [l, _, _],
      fragment(
        "array_lowercase(?) @> string_to_array(?, ',')::varchar[]",
        l.tags,
        ^Enum.map_join(tags, ",", &String.downcase/1)
      )
    )
  end

  defp visible_as(query, user) when is_nil(user) do
    query
    |> where(is_private: false)
  end

  defp visible_as(query, user) do
    query
    |> where([l, _, u], l.is_private == false or u.username == ^user)
  end
end
