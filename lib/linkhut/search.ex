defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Search.{Parser, Query}

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
