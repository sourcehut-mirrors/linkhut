defmodule Linkhut.Repo.Migrations.RenameArchivesToCrawlRuns do
  use Ecto.Migration

  def up do
    # Rename table
    execute "ALTER TABLE archives RENAME TO crawl_runs"

    # Rename FK column on snapshots
    execute "ALTER TABLE snapshots RENAME COLUMN archive_id TO crawl_run_id"

    # Rename indexes (non-constraint)
    execute "ALTER INDEX archives_link_id_state_index RENAME TO crawl_runs_link_id_state_index"
    execute "ALTER INDEX archives_inserted_at_index RENAME TO crawl_runs_inserted_at_index"
    execute "ALTER INDEX snapshots_archive_id_index RENAME TO snapshots_crawl_run_id_index"

    # Rename constraints (pkey rename also renames the backing index)
    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT archives_pkey TO crawl_runs_pkey"

    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT archives_link_id_fkey TO crawl_runs_link_id_fkey"

    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT archives_user_id_fkey TO crawl_runs_user_id_fkey"

    execute "ALTER TABLE snapshots RENAME CONSTRAINT snapshots_archive_id_fkey TO snapshots_crawl_run_id_fkey"
  end

  def down do
    # Rename constraints back
    execute "ALTER TABLE snapshots RENAME CONSTRAINT snapshots_crawl_run_id_fkey TO snapshots_archive_id_fkey"

    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT crawl_runs_user_id_fkey TO archives_user_id_fkey"

    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT crawl_runs_link_id_fkey TO archives_link_id_fkey"

    execute "ALTER TABLE crawl_runs RENAME CONSTRAINT crawl_runs_pkey TO archives_pkey"

    # Rename indexes back
    execute "ALTER INDEX snapshots_crawl_run_id_index RENAME TO snapshots_archive_id_index"
    execute "ALTER INDEX crawl_runs_inserted_at_index RENAME TO archives_inserted_at_index"
    execute "ALTER INDEX crawl_runs_link_id_state_index RENAME TO archives_link_id_state_index"

    # Rename FK column back
    execute "ALTER TABLE snapshots RENAME COLUMN crawl_run_id TO archive_id"

    # Rename table back
    execute "ALTER TABLE crawl_runs RENAME TO archives"
  end
end
