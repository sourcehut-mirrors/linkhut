defmodule Linkhut.Pagination do
  @moduledoc """
  Provides pagination capabilities to Ecto queries.
  """

  import Ecto.Query
  alias Linkhut.Pagination.Page
  alias Linkhut.Repo

  def page(query, page, per_page: per_page) when is_binary(page) do
    page = String.to_integer(page)
    page(query, page, per_page: per_page)
  end

  def page(query, page, per_page: per_page) do
    page = max(page - 1, 0)
    count = per_page

    result =
      query
      |> limit(^count)
      |> offset(^(page * per_page))
      |> Repo.all()

    total_count =
      Repo.one(from t in (query |> exclude(:preload) |> subquery()), select: count("*"))

    num_pages = ceil(total_count / per_page)
    has_next = (num_pages - 1) > page
    has_prev = page > 0

    %Page{
      has_next: has_next,
      has_prev: has_prev,
      prev_page: page,
      next_page: page + 2,
      page: page + 1,
      first: page * per_page + 1,
      last: Enum.min([(page + 1) * per_page, total_count]),
      count: total_count,
      entries: result,
      num_pages: num_pages
    }
  end
end
