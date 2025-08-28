defmodule Linkhut.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  def change do
    create table(:snapshots) do
      add :type, :string
      add :state, :string, default: "in_progress", null: false
      add :link_id, references(:links, on_delete: :delete_all)
      add :job_id, references(:oban_jobs, on_delete: :nilify_all)
      add :crawl_info, :map, default: %{}
      add :response_code, :integer
      add :file_size_bytes, :bigint
      add :processing_time_ms, :integer
      add :retry_count, :integer, default: 0
      add :failed_at, :utc_datetime
      add :storage_key, :string
      add :archive_metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:snapshots, [:link_id, :type])
    create index(:snapshots, [:link_id, :type, :state])
    create index(:snapshots, [:state])
    create index(:snapshots, [:retry_count])
  end
end
