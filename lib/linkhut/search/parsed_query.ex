defmodule Linkhut.Search.ParsedQuery do
  @moduledoc """
  Represents a fully parsed search query.

  Built by `Linkhut.Search.QueryParser.parse/1`.

  ## Fields

  - `raw` - the original, unmodified user input
  - `text_query` - cleaned text with operators removed, ready for `websearch_to_tsquery`
  - `terms` - list of individual non-operator words the user typed (for display)
  - `negated_terms` - words prefixed with `-` (excluded from highlighting)
  - `filters` - `%QueryFilters{}` with extracted `site:`, `inurl:` etc.
  - `language` - PostgreSQL text search configuration name (default: `"english"`)
  """

  alias Linkhut.Search.QueryFilters

  @type t() :: %__MODULE__{
          raw: String.t(),
          text_query: String.t(),
          terms: [String.t()],
          negated_terms: [String.t()],
          filters: QueryFilters.t(),
          language: String.t()
        }

  defstruct raw: "",
            text_query: "",
            terms: [],
            negated_terms: [],
            filters: %QueryFilters{},
            language: "english"
end
