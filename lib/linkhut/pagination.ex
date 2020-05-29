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
    count = per_page + 1

    result =
      query
      |> limit(^count)
      |> offset(^(page * per_page))
      |> Repo.all()

    has_next = length(result) == count
    has_prev = page > 0

    total_count =
      Repo.one(from t in (query |> exclude(:preload) |> subquery()), select: count("*"))

    %Page{
      has_next: has_next,
      has_prev: has_prev,
      prev_page: page,
      next_page: page + 2,
      page: page,
      first: page * per_page + 1,
      last: Enum.min([page + 1 * per_page, total_count]),
      count: total_count,
      entries: Enum.slice(result, 0, count - 1)
    }
  end
end
