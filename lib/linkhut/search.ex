defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Links
  alias Linkhut.Search.Context
  alias Linkhut.Search.QueryParser

  def search(context, query, params \\ [])

  def search(context, "", params) do
    links_for_context(context, params)
    |> preload([_, _, u], user: u)
    |> Links.ordering(params)
  end

  def search(context, query, params) do
    {cleaned_query, filters} = QueryParser.parse(query)

    # Update context with parsed query filters
    updated_context = %{context | query_filters: filters}

    if cleaned_query == "" do
      # If only site filters were provided, just filter without text search
      links_for_context(updated_context, params)
      |> select_merge([_, _, _], %{score: fragment("1.0") |> selected_as(:score)})
      |> preload([_, _, u], user: u)
      |> Links.ordering(params)
    else
      # Perform text search with site filtering
      links_for_context(updated_context, params)
      |> select_merge([_, _, _], %{
        score:
          fragment("ts_rank(search_vector, websearch_to_tsquery(?))", ^cleaned_query)
          |> selected_as(:score)
      })
      |> where(
        [l, _, _],
        fragment("? @@ websearch_to_tsquery(?)", l.search_vector, ^cleaned_query)
      )
      |> preload([_, _, u], user: u)
      |> Links.ordering(params)
    end
  end

  defp links_for_context(
         %Context{
           from: from,
           tagged_with: tags,
           visible_as: visible_as,
           url: url,
           query_filters: query_filters
         },
         params
       ) do
    Links.links(params)
    |> join(:inner, [l, _], u in assoc(l, :user))
    |> from_user(from)
    |> tagged_with(tags)
    |> visible_as(visible_as)
    |> matching(url)
    |> filtered_by_hosts(query_filters.sites)
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
    |> where([_, _, u], u.is_banned == false)
    |> where(is_private: false)
    |> where(is_unread: false)
    |> where([l], fragment("NOT 'via:ifttt' = ANY(?)", l.tags))
  end

  defp visible_as(query, user) do
    query
    |> where([_, _, u], u.is_banned == false or u.username == ^user)
    |> where([l, _, u], l.is_private == false or u.username == ^user)
    |> where([l, _, u], l.is_unread == false or u.username == ^user)
    |> where([l, _, u], fragment("NOT 'via:ifttt' = ANY(?)", l.tags) or u.username == ^user)
  end

  defp matching(query, url) when is_nil(url), do: query

  defp matching(query, url) do
    query
    |> where(url: ^url)
  end

  defp filtered_by_hosts(query, hosts) when is_nil(hosts) or hosts == [], do: query

  defp filtered_by_hosts(query, hosts) do
    query
    |> where([l, _, _], fragment("?->>'host' = ANY(?)", l.metadata, ^hosts))
  end
end
