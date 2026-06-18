defmodule LinkhutWeb.PaginationComponentsTest do
  use ExUnit.Case, async: true

  alias LinkhutWeb.PaginationComponents
  alias Linkhut.Pagination.Page

  defp page_numbers(total, current),
    do: PaginationComponents.page_numbers(%Page{num_pages: total, page: current})

  describe "page_numbers/1" do
    test "returns no numbers for a single page or fewer" do
      assert page_numbers(1, 1) == []
      assert page_numbers(0, 1) == []
    end

    test "lists every page without truncation up to 7 pages" do
      assert page_numbers(7, 4) == [1, 2, 3, 4, 5, 6, 7]
      assert page_numbers(5, 1) == [1, 2, 3, 4, 5]
    end

    test "truncates the tail when the current page is near the start" do
      assert page_numbers(12, 1) == [1, 2, 3, :ellipsis, 10, 11, 12]
      assert page_numbers(12, 2) == [1, 2, 3, :ellipsis, 10, 11, 12]
      assert page_numbers(12, 3) == [1, 2, 3, 4, :ellipsis, 11, 12]
    end

    test "truncates the head when the current page is near the end" do
      assert page_numbers(12, 12) == [1, 2, 3, :ellipsis, 10, 11, 12]
      assert page_numbers(12, 11) == [1, 2, 3, :ellipsis, 10, 11, 12]
      assert page_numbers(12, 10) == [1, 2, :ellipsis, 9, 10, 11, 12]
    end

    test "truncates both ends when the current page is in the middle" do
      assert page_numbers(12, 6) == [1, :ellipsis, 5, 6, 7, :ellipsis, 12]
    end
  end
end
