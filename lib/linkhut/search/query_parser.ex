defmodule Linkhut.Search.QueryParser do
  @moduledoc """
  Parser for search query modifiers like site: and inurl: terms.
  """

  alias Linkhut.Search.QueryFilters

  @doc """
  Parses a search query and extracts query filters.

  Returns a tuple {cleaned_query, query_filters} where:
  - cleaned_query is the original query with filter terms removed
  - query_filters is a QueryFilters struct containing extracted filters

  ## Examples

      iex> parse("hello world site:example.com")
      {"hello world", %Linkhut.Search.QueryFilters{sites: ["example.com"]}}

      iex> parse("site:foo.com site:bar.com test")
      {"test", %Linkhut.Search.QueryFilters{sites: ["foo.com", "bar.com"]}}

      iex> parse("inurl:admin inurl:dashboard phoenix")
      {"phoenix", %Linkhut.Search.QueryFilters{url_parts: ["admin", "dashboard"]}}

      iex> parse("no filters here")
      {"no filters here", %Linkhut.Search.QueryFilters{sites: [], url_parts: []}}
  """
  @spec parse(String.t()) :: {String.t(), QueryFilters.t()}
  def parse(query) when is_binary(query) do
    {cleaned_query, sites} = parse_sites(query)
    {cleaned_query, url_parts} = parse_inurl(cleaned_query)
    filters = QueryFilters.new(sites: sites, url_parts: url_parts)
    {cleaned_query, filters}
  end

  defp parse_sites(query) when is_binary(query) do
    site_regex = ~r/site:([^\s]+)/i

    sites =
      site_regex
      |> Regex.scan(query, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    cleaned_query =
      query
      |> String.replace(site_regex, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    {cleaned_query, sites}
  end

  defp parse_inurl(query) when is_binary(query) do
    inurl_regex = ~r/inurl:([^\s]+)/i

    url_parts =
      inurl_regex
      |> Regex.scan(query, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    cleaned_query =
      query
      |> String.replace(inurl_regex, "")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    {cleaned_query, url_parts}
  end
end
