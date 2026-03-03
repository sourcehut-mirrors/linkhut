defmodule Linkhut.Repo.Migrations.AddTrigramIndexesForTitleAndNotes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS links_title_trgm_index ON links USING GIN (title gin_trgm_ops)",
      "DROP INDEX IF EXISTS links_title_trgm_index"
    )

    execute(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS links_notes_trgm_index ON links USING GIN (notes gin_trgm_ops)",
      "DROP INDEX IF EXISTS links_notes_trgm_index"
    )
  end
end
