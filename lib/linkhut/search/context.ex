defmodule Linkhut.Search.Context do
  @moduledoc """
  A search context reduces the universe of links that a search query is evaluated against.
  """

  alias Linkhut.Accounts
  alias Linkhut.Search.QueryFilters

  @type t() :: %__MODULE__{
          from: Accounts.User.t(),
          tagged_with: [String.t()],
          visible_as: String.t(),
          url: String.t(),
          query_filters: QueryFilters.t()
        }

  defstruct from: nil, tagged_with: [], visible_as: nil, url: nil, query_filters: %QueryFilters{}

  def is_user?(%__MODULE__{from: from}) when is_nil(from), do: false
  def is_user?(%__MODULE__{from: _}), do: true
end
