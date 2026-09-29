defmodule Linkhut.Repo.Migrations.CreateArchivingEvents do
  use Ecto.Migration

  def up do
    create table(:archiving_events) do
      add :crawl_run_id, references(:crawl_runs, on_delete: :delete_all), null: false
      add :snapshot_id, :bigint
      add :source, :string
      add :event, :string, null: false
      add :level, :string, null: false, default: "info"
      add :data, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:archiving_events, [:crawl_run_id])

    drop_if_exists index(:crawl_runs, [:link_id, :state])

    alter table(:crawl_runs) do
      remove :steps
      remove :error
      remove :lock_version
      remove :state
      remove :total_size_bytes
      remove :final_url
      remove :preflight_meta
      remove :url
      remove :user_id
      remove :updated_at

      modify :link_id, references(:links, on_delete: :delete_all),
        from: references(:links, on_delete: :nilify_all)
    end

    create index(:crawl_runs, [:link_id])
  end

  def down do
    drop index(:crawl_runs, [:link_id])

    alter table(:crawl_runs) do
      add :steps, {:array, :map}, default: []
      add :error, :text
      add :lock_version, :integer, default: 0, null: false
      add :state, :string, default: "pending", null: false
      add :total_size_bytes, :bigint, default: 0, null: false
      add :final_url, :text
      add :preflight_meta, :map
      add :url, :text
      add :user_id, references(:users, on_delete: :nilify_all)
      add :updated_at, :utc_datetime, null: false, default: fragment("now()")

      modify :link_id, references(:links, on_delete: :nilify_all),
        from: references(:links, on_delete: :delete_all)
    end

    execute """
    UPDATE crawl_runs r
    SET url = l.url, user_id = l.user_id, updated_at = r.inserted_at
    FROM links l
    WHERE l.id = r.link_id
    """

    create index(:crawl_runs, [:link_id, :state])

    drop table(:archiving_events)
  end
end
