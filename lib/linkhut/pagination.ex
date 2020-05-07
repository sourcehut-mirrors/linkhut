defmodule Linkhut.Pagination do
  @moduledoc """
  Provides pagination capabilities to Ecto queries.
  """

  defmodule Page do
    @moduledoc """
    Defines a page.
    ## Fields
    * `entries` - a list entries contained in this page.
    * `has_next` - whether there's a previous page
    * `has_prev` - whether there's a next page
    * `prev_page` - number of the previous page
    * `next_page` - number of the next page
    * `page` - current page number
    * `first` - number of the first element in this page
    * `last` - number of the last element in this page
    * `count` - total number of elements
    """

    @type t :: %__MODULE__{
            entries: [any()] | [],
            has_next: boolean(),
            has_prev: boolean(),
            prev_page: integer(),
            next_page: integer(),
            page: integer(),
            first: integer(),
            last: integer(),
            count: integer()
          }

    defstruct [
      :entries,
      :has_next,
      :has_prev,
      :prev_page,
      :next_page,
      :page,
      :first,
      :last,
      :count
    ]
  end

  import Ecto.Query
  alias Linkhut.Repo

  def page(query, page, per_page: per_page) when is_nil(page) do
    page(query, 1, per_page: per_page)
  end

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
    total_count = Repo.one(from t in subquery(query), select: count("*"))

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
