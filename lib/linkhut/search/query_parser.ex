defmodule Linkhut.Search.QueryParser do
  @moduledoc """
  Parser for search query strings.

  Extracts structured operators (`site:`, `inurl:`) and produces a
  `%ParsedQuery{}` that downstream modules consume. Also sanitizes
  input (strips null bytes, caps length).
  """

  alias Linkhut.Search.ParsedQuery
  alias Linkhut.Search.QueryFilters

  @max_query_length 500

  @site_regex ~r/site:([^\s]+)/i
  @inurl_regex ~r/inurl:([^\s]+)/i

  @doc """
  Parses a raw search query string into a `%ParsedQuery{}`.

  Sanitizes input (strips null bytes, caps length), extracts `site:` and
  `inurl:` operators, identifies positive and negated terms, and returns
  the cleaned text suitable for `websearch_to_tsquery`.

  ## Examples

      iex> parse("hello world site:example.com")
      %ParsedQuery{raw: "hello world site:example.com", text_query: "hello world",
                   terms: ["hello", "world"],
                   filters: %QueryFilters{sites: ["example.com"]}}

      iex> parse("site:foo.com -excluded test")
      %ParsedQuery{raw: "site:foo.com -excluded test", text_query: "-excluded test",
                   terms: ["test"], negated_terms: ["excluded"],
                   filters: %QueryFilters{sites: ["foo.com"]}}
  """
  @spec parse(String.t()) :: ParsedQuery.t()
  def parse(query) when is_binary(query) do
    sanitized = sanitize(query)
    {after_sites, sites} = extract_filter(sanitized, @site_regex)
    {text_query, url_parts} = extract_filter(after_sites, @inurl_regex)
    {terms, negated_terms} = extract_terms(text_query)

    %ParsedQuery{
      raw: query,
      text_query: text_query,
      terms: terms,
      negated_terms: negated_terms,
      filters: QueryFilters.new(sites: sites, url_parts: url_parts)
    }
  end

  defp sanitize(query) do
    query
    |> String.replace(<<0>>, "")
    |> String.slice(0, @max_query_length)
    |> String.trim()
  end

  defp extract_filter(query, regex) do
    values =
      regex
      |> Regex.scan(query, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    cleaned_query =
      query
      |> String.replace(regex, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    {cleaned_query, values}
  end

  defp extract_terms(text_query) do
    tokens = Regex.scan(~r/-?"[^"]*"|\S+/, text_query) |> List.flatten()

    {negated, positive} =
      Enum.split_with(tokens, &String.starts_with?(&1, "-"))

    positive_terms =
      positive
      |> Enum.map(&String.replace(&1, ~r/^"|"$/, ""))
      |> Enum.reject(&(&1 == ""))

    negated_terms =
      negated
      |> Enum.map(&String.replace_leading(&1, "-", ""))
      |> Enum.map(&String.replace(&1, ~r/^"|"$/, ""))
      |> Enum.reject(&(&1 == ""))

    {positive_terms, negated_terms}
  end
end
