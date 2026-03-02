defmodule Linkhut.Search.QueryFiltersTest do
  use ExUnit.Case, async: true

  alias Linkhut.Search.QueryFilters

  describe "new/1" do
    test "creates empty filters by default" do
      filters = QueryFilters.new()
      assert filters.sites == []
      assert filters.url_parts == []
    end

    test "creates filters with provided values" do
      filters = QueryFilters.new(sites: ["example.com"], url_parts: ["admin"])
      assert filters.sites == ["example.com"]
      assert filters.url_parts == ["admin"]
    end
  end

  describe "has_filters?/1" do
    test "returns false for empty filters" do
      refute QueryFilters.has_filters?(QueryFilters.new())
    end

    test "returns true for filters with sites" do
      assert QueryFilters.has_filters?(QueryFilters.new(sites: ["example.com"]))
    end

    test "returns true for filters with url_parts" do
      assert QueryFilters.has_filters?(QueryFilters.new(url_parts: ["admin"]))
    end
  end
end
