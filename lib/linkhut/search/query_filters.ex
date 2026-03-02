defmodule Linkhut.Search.QueryFilters do
  @moduledoc """
  Structure for holding query-based filters extracted from search queries.

  This allows for extensible filtering based on query modifiers like:
  - site:example.com
  - inurl:admin
  - protocol:https (future)
  - type:pdf (future)
  etc.
  """

  @type t() :: %__MODULE__{
          sites: [String.t()],
          url_parts: [String.t()]
        }

  defstruct sites: [], url_parts: []

  @doc """
  Creates a new QueryFilters struct from parsed query components.
  """
  @spec new(Keyword.t()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end

  @doc """
  Returns true if any filters are set.
  """
  @spec has_filters?(t()) :: boolean()
  def has_filters?(%__MODULE__{sites: [], url_parts: []}), do: false
  def has_filters?(%__MODULE__{}), do: true
end
