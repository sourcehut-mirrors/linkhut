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

  describe "inurl filtering" do
    test "extracts single inurl filter" do
      {query, filters} = QueryParser.parse("hello world inurl:foobar")
      assert query == "hello world"
      assert filters.url_parts == ["foobar"]
    end

    test "extracts multiple inurl filters" do
      {query, filters} = QueryParser.parse("inurl:foobar inurl:dashboard test search")
      assert query == "test search"
      assert Enum.sort(filters.url_parts) == ["dashboard", "foobar"]
    end

    test "handles inurl filters at different positions" do
      {query, filters} = QueryParser.parse("search inurl:api more terms inurl:v1")
      assert query == "search more terms"
      assert Enum.sort(filters.url_parts) == ["api", "v1"]
    end

    test "handles query with only inurl filters" do
      {query, filters} = QueryParser.parse("inurl:foobar inurl:login")
      assert query == ""
      assert Enum.sort(filters.url_parts) == ["foobar", "login"]
    end

    test "converts inurl terms to lowercase" do
      {query, filters} = QueryParser.parse("inurl:FOOBAR inurl:DashBoard")
      assert query == ""
      assert Enum.sort(filters.url_parts) == ["dashboard", "foobar"]
    end

    test "deduplicates identical inurl filters" do
      {query, filters} = QueryParser.parse("inurl:foobar test inurl:foobar")
      assert query == "test"
      assert filters.url_parts == ["foobar"]
    end

    test "deduplicates case-insensitive inurl filters" do
      {query, filters} = QueryParser.parse("inurl:Foobar test inurl:foobar")
      assert query == "test"
      assert filters.url_parts == ["foobar"]
    end

    test "case insensitive inurl: prefix matching" do
      {query, filters} = QueryParser.parse("INURL:foobar InUrl:dashboard iNuRl:api")
      assert query == ""
      assert Enum.sort(filters.url_parts) == ["api", "dashboard", "foobar"]
    end
  end

  describe "combined filtering" do
    test "handles both site and inurl filters" do
      {query, filters} = QueryParser.parse("phoenix tutorial site:github.com inurl:foobar")
      assert query == "phoenix tutorial"
      assert filters.sites == ["github.com"]
      assert filters.url_parts == ["foobar"]
    end

    test "processes both filter types from complex query" do
      {query, filters} =
        QueryParser.parse("site:example.com inurl:api inurl:v1 documentation site:test.org")

      assert query == "documentation"
      assert Enum.sort(filters.sites) == ["example.com", "test.org"]
      assert Enum.sort(filters.url_parts) == ["api", "v1"]
    end

    test "query with only filters results in empty query string" do
      {query, filters} = QueryParser.parse("site:example.com inurl:foobar inurl:dashboard")
      assert query == ""
      assert filters.sites == ["example.com"]
      assert Enum.sort(filters.url_parts) == ["dashboard", "foobar"]
      assert QueryFilters.has_filters?(filters)
    end
  end
end
