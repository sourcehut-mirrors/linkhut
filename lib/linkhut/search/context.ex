defmodule Linkhut.Search.Context do
  @moduledoc """
  A search context reduces the universe of links that a search query is evaluated against.
  """

  alias Linkhut.Accounts
  alias Linkhut.Search.QueryFilters

  @type t() :: %__MODULE__{
          from: Accounts.User.t() | nil,
          tagged_with: [String.t()],
          visible_as: String.t() | nil,
          url: String.t() | nil,
          query_filters: QueryFilters.t()
        }

  defstruct from: nil, tagged_with: [], visible_as: nil, url: nil, query_filters: %QueryFilters{}

  @doc "Returns whether this context is scoped to a specific user."
  @spec user?(t()) :: boolean()
  def user?(%__MODULE__{from: nil}), do: false
  def user?(%__MODULE__{from: _}), do: true
end
