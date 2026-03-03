defmodule Linkhut.Repo.Migrations.AddTagsVector do
  use Ecto.Migration

  def up do
    # Add tags_vector column
    alter table(:links) do
      add :tags_vector, :tsvector
    end

    # GIN index for tags_vector
    execute "CREATE INDEX link_tags_search_index ON links USING GIN(tags_vector)"

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

    # Backfill in batches to avoid locking the entire table in one transaction
    execute """
    DO $$
    DECLARE
      rows_updated INT;
    BEGIN
      LOOP
        UPDATE links SET tags = tags
        WHERE id IN (
          SELECT id FROM links WHERE tags_vector IS NULL LIMIT 10000
        );
        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;
      END LOOP;
    END $$;
    """
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

    # Backfill search_vector with tags included again.
    # Use tags_vector IS NOT NULL as a progress marker — the restored trigger
    # does not write tags_vector, so we NULL it explicitly per batch.
    execute """
    DO $$
    DECLARE
      rows_updated INT;
    BEGIN
      LOOP
        UPDATE links SET tags = tags, tags_vector = NULL
        WHERE id IN (
          SELECT id FROM links WHERE tags_vector IS NOT NULL LIMIT 10000
        );
        GET DIAGNOSTICS rows_updated = ROW_COUNT;
        EXIT WHEN rows_updated = 0;
      END LOOP;
    END $$;
    """

    # Drop index and column
    execute "DROP INDEX link_tags_search_index"

    alter table(:links) do
      remove :tags_vector
    end
  end
end
