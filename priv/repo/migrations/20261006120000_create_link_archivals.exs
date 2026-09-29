defmodule Linkhut.Repo.Migrations.CreateLinkArchivals do
  use Ecto.Migration

  def up do
    execute "UPDATE snapshots SET state = 'crawling' WHERE state = 'retryable'"

    create table(:link_archivals) do
      add :link_id, references(:links, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :version, :string, null: false
      add :crawl_run_id, references(:crawl_runs, on_delete: :nilify_all)
      add :snapshot_id, references(:snapshots, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:link_archivals, [:link_id, :source])
    create index(:link_archivals, [:crawl_run_id])
    create index(:link_archivals, [:snapshot_id])
    create index(:link_archivals, [:updated_at])

    execute """
    INSERT INTO link_archivals (link_id, source, version, crawl_run_id, snapshot_id, inserted_at, updated_at)
    SELECT DISTINCT ON (s.link_id, s.source)
           s.link_id, s.source, s.crawler_meta->>'version', s.crawl_run_id, s.id,
           s.inserted_at, s.inserted_at
    FROM snapshots s
    JOIN links l ON l.id = s.link_id
    WHERE s.crawl_run_id IS NOT NULL
      AND s.state <> 'pending_deletion'
      AND s.crawler_meta ? 'version'
    ORDER BY s.link_id, s.source, s.inserted_at DESC, s.id DESC
    """

    drop constraint(:snapshots, :snapshots_crawl_run_id_check)
    drop index(:snapshots, [:crawl_run_id])

    alter table(:snapshots) do
      remove :crawl_run_id
    end
  end

  def down do
    alter table(:snapshots) do
      add :crawl_run_id, references(:crawl_runs, on_delete: :nilify_all)
    end

    execute """
    UPDATE snapshots s
    SET crawl_run_id = a.crawl_run_id
    FROM link_archivals a
    WHERE a.snapshot_id = s.id
    """

    create index(:snapshots, [:crawl_run_id])

    create constraint(:snapshots, :snapshots_crawl_run_id_check,
             check: "source = 'upload' OR crawl_run_id IS NOT NULL",
             validate: false
           )

    drop table(:link_archivals)
  end
end
