defmodule Linkhut.Search.QueryFiltersTest do
  use ExUnit.Case, async: true
  alias Linkhut.Search.QueryFilters

  describe "new/1" do
    test "creates empty filters by default" do
      filters = QueryFilters.new()
      assert filters.sites == []
    end

    test "creates filters with provided sites" do
      filters = QueryFilters.new(sites: ["example.com", "test.org"])
      assert filters.sites == ["example.com", "test.org"]
    end

    test "ignores unknown options" do
      filters = QueryFilters.new(sites: ["example.com"], unknown: "ignored")
      assert filters.sites == ["example.com"]
    end
  end

  describe "has_filters?/1" do
    test "returns false for empty filters" do
      filters = QueryFilters.new()
      assert QueryFilters.has_filters?(filters) == false
    end

    test "returns false for filters with empty sites" do
      filters = QueryFilters.new(sites: [])
      assert QueryFilters.has_filters?(filters) == false
    end

    test "returns true for filters with sites" do
      filters = QueryFilters.new(sites: ["example.com"])
      assert QueryFilters.has_filters?(filters) == true
    end
  end
end
