defmodule Linkhut.Repo.Migrations.AddTagsVector do
  use Ecto.Migration

  # Disable the wrapping transaction so each execute/batch runs independently.
  # This lets the backfill commit per-batch, avoiding massive dead-tuple bloat.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Add tags_vector column
    execute "ALTER TABLE links ADD COLUMN IF NOT EXISTS tags_vector tsvector"

    # GIN index for tags_vector
    execute "CREATE INDEX IF NOT EXISTS link_tags_search_index ON links USING GIN(tags_vector)"

    # Replace trigger function: search_vector gets title(A) + notes(B) only,
    # tags_vector gets tags via to_tsvector('simple', ...) with positions
    execute """
    CREATE OR REPLACE FUNCTION link_search_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.search_vector :=
        setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.title,'')), 'A') ||
        setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.notes,'')), 'B');
      NEW.tags_vector :=
        to_tsvector('simple', coalesce(array_to_string(array_lowercase(NEW.tags), ' '), ''));
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """

    # Flush pending DDL so the new column/index/function are committed
    # before the backfill queries reference them.
    flush()

    # Backfill in batches — each batch is its own transaction so dead tuples
    # can be reclaimed between batches and we don't bloat the table.
    backfill_up()
  end

  def down do
    # Restore original trigger function (tags back in search_vector)
    execute """
    CREATE OR REPLACE FUNCTION link_search_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.search_vector :=
        setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.title,'')), 'A') ||
        setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.notes,'')), 'B') ||
        setweight(array_to_tsvector(coalesce(array_lowercase(NEW.tags),'{}')::text[]), 'D');
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """

    # Flush so the restored trigger function is committed before backfill.
    flush()

    # Backfill search_vector with tags included again.
    backfill_down()

    # Drop index and column
    execute "DROP INDEX IF EXISTS link_tags_search_index"
    execute "ALTER TABLE links DROP COLUMN IF EXISTS tags_vector"
  end

  @batch_size 10_000
  @query_timeout 120_000

  defp backfill_up do
    {:ok, %{rows: [[total]]}} =
      repo().query("SELECT count(*) FROM links WHERE tags_vector IS NULL", [], timeout: @query_timeout)

    if total > 0 do
      batches = ceil(total / @batch_size)

      Enum.each(1..batches, fn _batch ->
        repo().query!(
          "UPDATE links SET tags = tags WHERE id IN (SELECT id FROM links WHERE tags_vector IS NULL LIMIT $1)",
          [@batch_size],
          timeout: @query_timeout
        )
      end)
    end
  end

  defp backfill_down do
    {:ok, %{rows: [[total]]}} =
      repo().query("SELECT count(*) FROM links WHERE tags_vector IS NOT NULL", [], timeout: @query_timeout)

    if total > 0 do
      batches = ceil(total / @batch_size)

      Enum.each(1..batches, fn _batch ->
        repo().query!(
          "UPDATE links SET tags = tags, tags_vector = NULL WHERE id IN (SELECT id FROM links WHERE tags_vector IS NOT NULL LIMIT $1)",
          [@batch_size],
          timeout: @query_timeout
        )
      end)
    end
  end
end
