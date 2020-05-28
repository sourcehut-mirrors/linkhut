defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Search.{Context, Parser, Query}

  def search(context, query, _params \\ []) do
    links_for_context(context)
    |> where([l, _], fragment("? @@ phraseto_tsquery(?)", l.search_vector, ^query))
    |> preload([_, u], [user: u])
  end

  def links_for_context(%Context{user: user, tags: tags, issuer: owner}) do
    Link
    |> join(:inner, [l], u in assoc(l, :user))
    |> with_user(user)
    |> with_tags(tags)
    |> with_private_links_belonging_to(owner)
  end

  defp with_user(query, user) when is_nil(user), do: query

  defp with_user(query, user) do
    query
    |> where([_, u], u.username == ^user)
  end

  defp with_tags(query, tags) when is_nil(tags) or length(tags) == 0, do: query

  defp with_tags(query, tags) do
    query
    |> where(
      [l, _],
      fragment("? @> string_to_array(?, ',')::varchar[]", l.tags, ^Enum.join(tags, ","))
    )
  end

  defp with_private_links_belonging_to(query, user) when is_nil(user) do
    query
    |> where(is_private: false)
  end

  defp with_private_links_belonging_to(query, user) do
    query
    |> where([l, u], l.is_private == false or u.username == ^user)
  end

  @doc """
  Parses a list of terms.

  ### Examples

      iex> parse(["~mlb", ":tag", "foo", "bar"])
      %Query{
        quotes: [],
        tags: ["tag"],
        users: ["mlb"],
        words: "foo bar"
      }
  """
  @spec parse([String.t()]) :: Query.t()
  def parse(terms) when is_list(terms), do: parse(Enum.join(terms, " "))

  @doc """
  Parses a search string.

  ### Examples

      iex> parse("~mlb :tag foo bar")
      %Query{
        quotes: [],
        tags: ["tag"],
        users: ["mlb"],
        words: "foo bar"
      }
  """
  @spec parse(String.t()) :: Query.t()
  def parse(query) when is_binary(query) do
    query
    |> Parser.parse()
    |> Query.query()
  end

  @spec search(Query.t()) :: Elixir.Ecto.Query.t()
  def search(search_query) do
    matched =
      Link
      |> select([:url, :user_id])
      |> intersect_all(^match_quotes(search_query.quotes))
      |> intersect_all(^match_tags(search_query.tags))
      |> intersect_all(^match_users(search_query.users))
      |> intersect_all(^match_words(search_query.words))

    Link
    |> join(:inner, [l], m in subquery(matched), on: l.url == m.url and l.user_id == m.user_id)
  end

  defp match_all() do
    Link
    |> select([:url, :user_id])
    |> where(is_private: false)
  end

  defp match_quotes(quotes) when is_nil(quotes) or length(quotes) == 0, do: match_all()

  defp match_quotes(quotes) do
    Enum.reduce(quotes, match_all(), fn quote, query ->
      query
      |> where(
        [l],
        fragment("to_tsvector(?) @@ phraseto_tsquery(?)", l.title, ^quote) or
          fragment("to_tsvector(?) @@ phraseto_tsquery(?)", l.notes, ^quote)
      )
    end)
  end

  defp match_tags(tags) when length(tags) == 0, do: match_all()

  defp match_tags(tags) do
    match_all()
    |> where(
      [l],
      fragment("? @> string_to_array(?, ',')::varchar[]", l.tags, ^Enum.join(tags, ","))
    )
  end

  defp match_users(users) when length(users) == 0, do: match_all()

  defp match_users(users) do
    match_all()
    |> join(:inner, [l], u in User, on: [id: l.user_id])
    |> where([_, u], u.username in ^users)
  end

  defp match_words(""), do: match_all()

  defp match_words(words) do
    match_all()
    |> where(
      [l],
      fragment("to_tsvector(?) @@ plainto_tsquery(?)", l.title, ^words) or
        fragment("to_tsvector(?) @@ plainto_tsquery(?)", l.notes, ^words)
    )
  end
end
