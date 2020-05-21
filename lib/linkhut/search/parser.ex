defmodule Linkhut.Search.Parser do
  @moduledoc """
  A very simple parser.
  """

  alias Linkhut.Search.Term

  @doc """
  Parses a query string into a list of search terms.

  ## Examples

      iex> parse("~username :foo \\"string to match exactly\\" bar")
      [user: "username", tag: "foo", quote: "string to match exactly", word: "bar"]

  """
  @spec parse(String.t()) :: [Term.t()]
  def parse(string) do
    string
    |> do_parse()
  end

  defp do_parse(string, acc \\ [])
  defp do_parse("", acc), do: acc
  defp do_parse(~s( ) <> rest, acc), do: do_parse(rest, acc)
  defp do_parse(~s(") <> rest, acc), do: do_parse(rest, acc, {:quote, ""})
  defp do_parse(~s(~) <> rest, acc), do: do_parse(rest, acc, {:user, ""})
  defp do_parse(~s(:) <> rest, acc), do: do_parse(rest, acc, {:tag, ""})

  defp do_parse(<<char::binary-size(1), rest::binary>>, acc) do
    do_parse(rest, acc, {:word, char})
  end

  defp do_parse("", acc, token), do: acc ++ [token]

  defp do_parse(~s( ) <> rest, acc, {type, _} = token) when type != :quote do
    do_parse(rest, acc ++ [token])
  end

  defp do_parse(~s(") <> rest, acc, {:quote, val}) do
    do_parse(rest, acc ++ [{:quote, String.trim(val)}])
  end

  defp do_parse(~s(") <> rest, acc, token) do
    do_parse(rest, acc ++ [token])
  end

  defp do_parse(<<char::binary-size(1), rest::binary>>, acc, {type, val}) do
    do_parse(rest, acc, {type, val <> char})
  end
end
