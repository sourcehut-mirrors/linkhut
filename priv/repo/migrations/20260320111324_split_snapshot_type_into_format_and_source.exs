defmodule Linkhut.Repo.Migrations.SplitSnapshotTypeIntoFormatAndSource do
  use Ecto.Migration

  def change do
    # Rename type -> source
    execute "ALTER TABLE snapshots RENAME COLUMN type TO source",
            "ALTER TABLE snapshots RENAME COLUMN source TO type"

    # Add format, backfill, set NOT NULL
    alter table(:snapshots) do
      add :format, :string
    end

    flush()

    execute """
    UPDATE snapshots SET format = CASE
      WHEN source = 'singlefile' THEN 'webpage'
      WHEN source = 'wayback' THEN 'reference'
      WHEN source = 'httpfetch' THEN
        CASE
          WHEN archive_metadata->>'content_type' LIKE 'application/pdf' THEN 'pdf'
          WHEN archive_metadata->>'content_type' LIKE 'text/plain%' THEN 'text'
          WHEN archive_metadata->>'content_type' LIKE 'text/markdown%' THEN 'text'
          ELSE 'webpage'
        END
      ELSE 'webpage'
    END
    """

    execute "ALTER TABLE snapshots ALTER COLUMN format SET NOT NULL"

    # Drop old indexes (auto-named from 20250321145536_create_snapshots)
    drop index(:snapshots, [:link_id, :type], name: :snapshots_link_id_type_index)
    drop index(:snapshots, [:link_id, :type, :state], name: :snapshots_link_id_type_state_index)

    # New index
    create index(:snapshots, [:link_id, :format, :state])

    # Nullable crawl_run_id
    execute "ALTER TABLE snapshots ALTER COLUMN crawl_run_id DROP NOT NULL",
            "ALTER TABLE snapshots ALTER COLUMN crawl_run_id SET NOT NULL"

    # CHECK constraints
    execute """
            ALTER TABLE snapshots ADD CONSTRAINT snapshots_crawl_run_id_check
              CHECK (source = 'upload' OR crawl_run_id IS NOT NULL)
            """,
            "ALTER TABLE snapshots DROP CONSTRAINT snapshots_crawl_run_id_check"

    execute """
            ALTER TABLE snapshots ADD CONSTRAINT snapshots_format_source_check CHECK (
              (source = 'singlefile' AND format = 'webpage') OR
              (source = 'httpfetch'  AND format IN ('webpage', 'pdf', 'text')) OR
              (source = 'wayback'    AND format = 'reference') OR
              (source = 'upload'     AND format IN ('webpage', 'pdf', 'text'))
            )
            """,
            "ALTER TABLE snapshots DROP CONSTRAINT snapshots_format_source_check"
  end
end
