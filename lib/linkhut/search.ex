defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Links
  alias Linkhut.Network
  alias Linkhut.Search.Context
  alias Linkhut.Search.ParsedQuery
  alias Linkhut.Search.QueryParser
  alias Linkhut.Search.Ranking

  @doc """
  Searches links within the given context.

  Parses the raw query string to extract operators and text, applies
  context-based filtering (user, tags, visibility, URL), then applies
  full-text search ranking when a text query is present.
  """
  @spec search(Context.t(), String.t(), keyword()) :: Ecto.Query.t()
  def search(context, raw_query, params \\ [])

  def search(context, raw_query, params) when is_binary(raw_query) do
    case String.trim(raw_query) do
      "" -> search_without_query(context, params)
      trimmed -> search_with_query(context, trimmed, params)
    end
  end

  defp search_without_query(context, params) do
    parsed = %ParsedQuery{}

    links_for_context(context, params)
    |> Ranking.apply_scoring(parsed)
    |> preload([_, _, u], user: u)
    |> Links.ordering(params)
  end

  defp search_with_query(%Context{} = context, raw_query, params) do
    parsed = QueryParser.parse(raw_query)
    updated_context = %Context{context | query_filters: parsed.filters}

    links_for_context(updated_context, params)
    |> Ranking.apply_text_filter(parsed)
    |> Ranking.apply_scoring(parsed)
    |> preload([_, _, u], user: u)
    |> Links.ordering(params)
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
    |> from_user(from)
    |> tagged_with(tags)
    |> visible_as(visible_as)
    |> matching(url)
    |> filtered_by_hosts(query_filters.sites)
    |> filtered_by_url_terms(query_filters.url_parts)
  end

  defp from_user(query, nil), do: query

  defp from_user(query, user) do
    where(query, [_, _, u], u.id == ^user.id)
  end

  defp tagged_with(query, []), do: query

  defp tagged_with(query, tags) do
    where(
      query,
      [l, _, _],
      fragment(
        "array_lowercase(?) @> string_to_array(?, ',')::varchar[]",
        l.tags,
        ^Enum.map_join(tags, ",", &String.downcase/1)
      )
    )
  end

  defp visible_as(query, nil) do
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

  defp matching(query, nil), do: query

  defp matching(query, url) do
    where(query, normalized_url: ^Network.normalize_url(url))
  end

  defp filtered_by_hosts(query, []), do: query

  defp filtered_by_hosts(query, hosts) do
    where(query, [l, _, _], fragment("?->>'host' = ANY(?)", l.metadata, ^hosts))
  end

  defp filtered_by_url_terms(query, []), do: query

  defp filtered_by_url_terms(query, url_parts) do
    Enum.reduce(url_parts, query, fn term, acc_query ->
      sanitized = sanitize_like_pattern(term)
      where(acc_query, [l, _, _], ilike(l.url, ^"%#{sanitized}%"))
    end)
  end

  defp sanitize_like_pattern(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
