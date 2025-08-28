defmodule Linkhut.Search.QueryParserTest do
  use ExUnit.Case, async: true
  alias Linkhut.Search.QueryParser
  alias Linkhut.Search.QueryFilters

  describe "site filtering" do
    test "extracts single site filter" do
      {query, filters} = QueryParser.parse("hello world site:example.com")
      assert query == "hello world"
      assert filters.sites == ["example.com"]
    end

    test "extracts multiple site filters" do
      {query, filters} = QueryParser.parse("site:foo.com site:bar.com test search")
      assert query == "test search"
      assert Enum.sort(filters.sites) == ["bar.com", "foo.com"]
    end

    test "handles site filters at different positions" do
      {query, filters} = QueryParser.parse("search site:example.com more terms site:test.org")
      assert query == "search more terms"
      assert Enum.sort(filters.sites) == ["example.com", "test.org"]
    end

    test "handles query with only site filters" do
      {query, filters} = QueryParser.parse("site:example.com site:test.org")
      assert query == ""
      assert Enum.sort(filters.sites) == ["example.com", "test.org"]
    end

    test "returns empty sites list when no site filters present" do
      {query, filters} = QueryParser.parse("regular search query")
      assert query == "regular search query"
      refute QueryFilters.has_filters?(filters)
    end

    test "handles empty query" do
      {query, filters} = QueryParser.parse("")
      assert query == ""
      refute QueryFilters.has_filters?(filters)
    end

    test "normalizes whitespace in cleaned query" do
      {query, filters} = QueryParser.parse("  hello   site:example.com   world  ")
      assert query == "hello world"
      assert filters.sites == ["example.com"]
    end

    test "converts site hosts to lowercase" do
      {query, filters} = QueryParser.parse("site:EXAMPLE.COM site:Test.ORG")
      assert query == ""
      assert Enum.sort(filters.sites) == ["example.com", "test.org"]
    end

    test "deduplicates identical site filters" do
      {query, filters} = QueryParser.parse("site:example.com test site:example.com")
      assert query == "test"
      assert filters.sites == ["example.com"]
    end

    test "deduplicates case-insensitive site filters" do
      {query, filters} = QueryParser.parse("site:Example.COM test site:example.com")
      assert query == "test"
      assert filters.sites == ["example.com"]
    end

    test "handles complex domains and subdomains" do
      {query, filters} = QueryParser.parse("site:blog.example.co.uk site:api.test-site.com")
      assert query == ""
      assert Enum.sort(filters.sites) == ["api.test-site.com", "blog.example.co.uk"]
    end

    test "case insensitive site: prefix matching" do
      {query, filters} = QueryParser.parse("SITE:example.com Site:test.org sITe:foo.bar")
      assert query == ""
      assert Enum.sort(filters.sites) == ["example.com", "foo.bar", "test.org"]
    end
  end
end
