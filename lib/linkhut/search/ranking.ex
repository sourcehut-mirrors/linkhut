defmodule Linkhut.Search.Ranking do
  @moduledoc """
  Encapsulates all full-text search ranking logic.

  Provides Ecto query fragments for tsvector matching and scoring.
  This is the single source of truth for how search relevance is computed.

  ## Search Ranking Hierarchy

  The `search_vector` column is populated by a PostgreSQL trigger with these weights:

  | Weight | Source    | ts_rank weight | Rationale                                    |
  |--------|-----------|----------------|----------------------------------------------|
  | A      | title     | 1.0            | Title is the strongest relevance signal      |
  | B      | notes     | 0.4            | User-authored description, high intent       |
  | C      | (unused)  | 0.2            | Reserved                                     |
  | D      | tags      | 0.1            | Tags are categorical, not textual relevance  |

  Scoring uses `ts_rank` with explicit weights `{0.1, 0.2, 0.4, 1.0}` for
  `{D, C, B, A}` and no normalization (flag 0).
  """

  import Ecto.Query

  alias Linkhut.Search.ParsedQuery

  @doc """
  Adds a `WHERE` clause that filters links by full-text match.
  No-op when the parsed query has no text.
  """
  @spec apply_text_filter(Ecto.Query.t(), ParsedQuery.t()) :: Ecto.Query.t()
  def apply_text_filter(query, %ParsedQuery{text_query: ""}), do: query

  def apply_text_filter(query, %ParsedQuery{text_query: text_query, language: language}) do
    where(
      query,
      [l, _, _],
      fragment(
        "? @@ websearch_to_tsquery(?::varchar::regconfig, ?)",
        l.search_vector,
        ^language,
        ^text_query
      )
    )
  end

  @doc """
  Adds a `score` virtual field to the SELECT via `select_merge`.
  When there is no text query, score is hardcoded to 1.0.
  """
  @spec apply_scoring(Ecto.Query.t(), ParsedQuery.t()) :: Ecto.Query.t()
  def apply_scoring(query, %ParsedQuery{text_query: ""}) do
    select_merge(query, [_, _, _], %{
      score: fragment("1.0") |> selected_as(:score)
    })
  end

  def apply_scoring(query, %ParsedQuery{text_query: text_query, language: language}) do
    select_merge(query, [_, _, _], %{
      score:
        fragment(
          "ts_rank('{0.1, 0.2, 0.4, 1.0}', search_vector, websearch_to_tsquery(?::varchar::regconfig, ?))",
          ^language,
          ^text_query
        )
        |> selected_as(:score)
    })
  end
end
