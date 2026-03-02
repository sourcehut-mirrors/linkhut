defmodule Linkhut.Search.QueryParserTest do
  use ExUnit.Case, async: true

  alias Linkhut.Search.ParsedQuery
  alias Linkhut.Search.QueryFilters
  alias Linkhut.Search.QueryParser

  for {operator, field} <- [{"site", :sites}, {"inurl", :url_parts}] do
    @operator operator
    @field field

    describe "#{@operator}: filter extraction" do
      test "extracts single filter" do
        %ParsedQuery{text_query: text, filters: filters} =
          QueryParser.parse("hello #{@operator}:example.com world")

        assert text == "hello world"
        assert Map.fetch!(filters, @field) == ["example.com"]
      end

      test "extracts multiple filters" do
        %ParsedQuery{text_query: text, filters: filters} =
          QueryParser.parse("#{@operator}:foo.com #{@operator}:bar.com search")

        assert text == "search"
        assert Enum.sort(Map.fetch!(filters, @field)) == ["bar.com", "foo.com"]
      end

      test "produces empty text when only filters present" do
        %ParsedQuery{text_query: text, terms: terms} =
          QueryParser.parse("#{@operator}:foo.com #{@operator}:bar.com")

        assert text == ""
        assert terms == []
      end

      test "deduplicates case-insensitively" do
        %ParsedQuery{filters: filters} =
          QueryParser.parse("#{@operator}:Foo.COM test #{@operator}:foo.com")

        assert Map.fetch!(filters, @field) == ["foo.com"]
      end

      test "recognizes operator regardless of casing" do
        upper = String.upcase(@operator)
        mixed = String.capitalize(@operator)

        %ParsedQuery{text_query: text, filters: filters} =
          QueryParser.parse("#{upper}:a.com #{mixed}:b.com")

        assert text == ""
        assert Enum.sort(Map.fetch!(filters, @field)) == ["a.com", "b.com"]
      end
    end
  end

  describe "site-specific" do
    test "handles complex domains and subdomains" do
      %ParsedQuery{filters: filters} =
        QueryParser.parse("site:blog.example.co.uk site:api.test-site.com")

      assert Enum.sort(filters.sites) == ["api.test-site.com", "blog.example.co.uk"]
    end
  end

  describe "combined filters" do
    test "handles both site and inurl filters together" do
      %ParsedQuery{text_query: text, filters: filters} =
        QueryParser.parse("phoenix site:github.com inurl:api")

      assert text == "phoenix"
      assert filters.sites == ["github.com"]
      assert filters.url_parts == ["api"]
      assert QueryFilters.has_filters?(filters)
    end
  end

  describe "term extraction" do
    test "extracts simple terms" do
      assert %ParsedQuery{terms: ["hello", "world"]} = QueryParser.parse("hello world")
    end

    test "extracts quoted phrases as single terms" do
      assert %ParsedQuery{terms: ["exact phrase", "other"]} =
               QueryParser.parse(~s("exact phrase" other))
    end

    test "separates negated terms" do
      %ParsedQuery{terms: terms, negated_terms: negated} =
        QueryParser.parse("-excluded included")

      assert terms == ["included"]
      assert negated == ["excluded"]
    end

    test "handles negated quoted phrases" do
      %ParsedQuery{terms: terms, negated_terms: negated} =
        QueryParser.parse(~s(-"exact phrase"))

      assert terms == []
      assert negated == ["exact phrase"]
    end

    test "excludes operators from terms" do
      assert %ParsedQuery{terms: ["elixir", "phoenix"]} =
               QueryParser.parse("site:example.com elixir inurl:api phoenix")
    end

    test "empty query produces empty terms" do
      assert %ParsedQuery{terms: [], negated_terms: []} = QueryParser.parse("")
    end
  end

  describe "input sanitization" do
    test "strips null bytes" do
      assert %ParsedQuery{text_query: "helloworld"} = QueryParser.parse("hello\0world")
    end

    test "truncates input to 500 characters" do
      %ParsedQuery{text_query: text} = QueryParser.parse(String.duplicate("a", 600))
      assert String.length(text) == 500
    end

    test "preserves raw field even when input is sanitized" do
      input = "  hello\0world  "
      assert %ParsedQuery{raw: ^input} = QueryParser.parse(input)
    end
  end

  describe "edge cases" do
    test "operator with no value is not extracted as filter" do
      parsed = QueryParser.parse("site: hello")

      refute QueryFilters.has_filters?(parsed.filters)
      assert "hello" in parsed.terms
    end

    test "plain query has no filters" do
      parsed = QueryParser.parse("just some words")

      refute QueryFilters.has_filters?(parsed.filters)
      assert parsed.terms == ["just", "some", "words"]
    end
  end
end
