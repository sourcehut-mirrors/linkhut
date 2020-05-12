defmodule Linkhut.Pagination.Page do
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

  @type element :: any

  @type t :: %__MODULE__{
          entries: [element()] | [],
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
