defmodule Linkhut.Search.Ranking do
  @moduledoc """
  Encapsulates all full-text search ranking logic.

  Provides Ecto query fragments for tsvector matching and scoring.
  This is the single source of truth for how search relevance is computed.

  ## Search Ranking Hierarchy

  Two tsvector columns are populated by a PostgreSQL trigger:

  - `search_vector` — title (weight A) + notes (weight B), using the link's language config.
  - `tags_vector` — tags, using `'simple'` config (no stemming/stop-words).

  `search_vector` scoring uses `ts_rank` with explicit weights `{0.1, 0.2, 0.4, 1.0}` for
  `{D, C, B, A}` and no normalization (flag 0). `tags_vector` scoring uses plain `ts_rank`
  which naturally produces lower values than weighted title/notes matches.

  ## Hybrid Search

  When the query contains terms >= 3 characters, a hybrid strategy is used:
  FTS OR grep-like (`~*` with `\\m` word boundary) matching. This ensures
  partial/unstemmed terms (e.g., "postmarket" for "postmarketOS") are found.
  """

  import Ecto.Query

  alias Linkhut.Search.ParsedQuery

  @fts_weight 10.0
  @tags_weight 1.0
  @grep_boost 0.5
  @min_grep_length 3

  @doc """
  Adds a `WHERE` clause that filters links by full-text match.
  No-op when the parsed query has no text.
  """
  @spec apply_text_filter(Ecto.Query.t(), ParsedQuery.t()) :: Ecto.Query.t()
  def apply_text_filter(query, %ParsedQuery{text_query: ""}), do: query

  def apply_text_filter(query, %ParsedQuery{} = parsed) do
    case grep_eligible_terms(parsed.terms) do
      [] -> fts_only_filter(query, parsed)
      eligible -> hybrid_filter(query, parsed, eligible)
    end
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

  def apply_scoring(query, %ParsedQuery{} = parsed) do
    case grep_eligible_terms(parsed.terms) do
      [] -> fts_only_scoring(query, parsed)
      eligible -> hybrid_scoring(query, parsed, eligible)
    end
  end

  # FTS-only filter: match on search_vector OR tags_vector.
  # Both vectors are referenced as bare SQL (not via Ecto bindings) because
  # neither is defined in the Link schema — they are trigger-managed columns.
  defp fts_only_filter(query, %ParsedQuery{text_query: text_query, language: language}) do
    where(
      query,
      [_, _, _],
      fragment(
        "search_vector @@ websearch_to_tsquery(?::varchar::regconfig, ?)",
        ^language,
        ^text_query
      ) or
        fragment(
          "tags_vector @@ websearch_to_tsquery('simple', ?)",
          ^text_query
        )
    )
  end

  # FTS-only scoring: search_vector rank + tags_vector rank.
  # No weight multipliers here — raw ts_rank values are only compared against each
  # other (no grep signal). Weights are applied in the hybrid path instead.
  # COALESCE guards against NULL tags_vector (e.g. during partial backfill).
  defp fts_only_scoring(query, %ParsedQuery{text_query: text_query, language: language}) do
    select_merge(query, [_, _, _], %{
      score:
        fragment(
          """
          ts_rank('{0.1, 0.2, 0.4, 1.0}', search_vector, websearch_to_tsquery(?::varchar::regconfig, ?))
          +
          coalesce(ts_rank(tags_vector, websearch_to_tsquery('simple', ?)), 0)
          """,
          ^language,
          ^text_query,
          ^text_query
        )
        |> selected_as(:score)
    })
  end

  # Hybrid filter: FTS match OR tags match OR all grep-eligible terms match
  defp hybrid_filter(query, %ParsedQuery{text_query: text_query, language: language}, eligible) do
    fts_dynamic =
      dynamic(
        [_, _, _],
        fragment(
          "search_vector @@ websearch_to_tsquery(?::varchar::regconfig, ?)",
          ^language,
          ^text_query
        )
      )

    tags_dynamic =
      dynamic(
        [_, _, _],
        fragment(
          "tags_vector @@ websearch_to_tsquery('simple', ?)",
          ^text_query
        )
      )

    grep_dynamic = build_grep_where(eligible)
    combined = dynamic([], ^fts_dynamic or ^tags_dynamic or ^grep_dynamic)
    where(query, ^combined)
  end

  # Hybrid scoring: FTS score * weight + tags score * weight + grep boost per matching term.
  # Uses a correlated subquery with unnest to handle variable number of patterns
  # in a single fragment (avoids Ecto's dynamic nesting restriction in select_merge).
  # Note: search_vector and tags_vector are referenced as bare SQL in the fragment string
  # (not via ?) because tags_vector is not in the Ecto schema.
  defp hybrid_scoring(query, %ParsedQuery{text_query: text_query, language: language}, eligible) do
    patterns = Enum.map(eligible, &term_to_pattern/1)

    select_merge(query, [l, _, _], %{
      score:
        fragment(
          """
          CASE WHEN search_vector @@ websearch_to_tsquery(?::varchar::regconfig, ?)
          THEN ts_rank('{0.1, 0.2, 0.4, 1.0}', search_vector, websearch_to_tsquery(?::varchar::regconfig, ?)) * ?
          ELSE 0 END
          +
          CASE WHEN tags_vector @@ websearch_to_tsquery('simple', ?)
          THEN ts_rank(tags_vector, websearch_to_tsquery('simple', ?)) * ?
          ELSE 0 END
          +
          coalesce((SELECT count(*)::float FROM unnest(?::text[]) AS pat
           WHERE coalesce(?, '') ~* pat OR coalesce(?, '') ~* pat), 0) * ?
          """,
          ^language,
          ^text_query,
          ^language,
          ^text_query,
          ^@fts_weight,
          ^text_query,
          ^text_query,
          ^@tags_weight,
          ^patterns,
          l.title,
          l.notes,
          ^@grep_boost
        )
        |> selected_as(:score)
    })
  end

  defp grep_eligible_terms(terms) do
    Enum.filter(terms, &(String.length(&1) >= @min_grep_length))
  end

  defp term_to_pattern(term) do
    "\\m" <> Regex.escape(term)
  end

  # AND all per-term grep conditions together
  defp build_grep_where(eligible) do
    eligible
    |> Enum.map(&build_term_grep/1)
    |> Enum.reduce(fn term_dynamic, acc ->
      dynamic([], ^acc and ^term_dynamic)
    end)
  end

  # Single term: match on title OR notes with ~* word boundary
  defp build_term_grep(term) do
    pattern = term_to_pattern(term)

    dynamic(
      [l, _, _],
      fragment("coalesce(?, '') ~* ?", l.title, ^pattern) or
        fragment("coalesce(?, '') ~* ?", l.notes, ^pattern)
    )
  end
end
