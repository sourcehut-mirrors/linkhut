defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  alias Linkhut.Search.{Parser, Query}

  @doc """
  Parses a list of terms.

  ### Examples

      iex> parse(["~mlb", ":tag", "foo", "bar"])
      %Query{
        quotes: nil,
        tags: ["tag"],
        users: ["mlb"],
        words: ["foo", "bar"]
      }
  """
  @spec parse([String.t()]) :: Query.t()
  def parse(terms) when is_list(terms), do: parse(Enum.join(terms, " "))

  @doc """
  Parses a search string.

  ### Examples

      iex> parse("~mlb :tag foo bar")
      %Query{
        quotes: nil,
        tags: ["tag"],
        users: ["mlb"],
        words: ["foo", "bar"]
      }
  """
  @spec parse(String.t()) :: Query.t()
  def parse(query) when is_binary(query) do
    query
    |> Parser.parse()
    |> Query.query()
  end
end
