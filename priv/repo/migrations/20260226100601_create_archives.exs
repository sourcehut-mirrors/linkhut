defmodule Linkhut.Repo.Migrations.CreateArchives do
  use Ecto.Migration

  def change do
    create table(:archives) do
      add :link_id, references(:links, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :job_id, references(:oban_jobs, type: :bigint, on_delete: :nilify_all)
      add :url, :text
      add :final_url, :text
      add :state, :string, default: "active", null: false
      add :preflight_meta, :map
      add :steps, {:array, :map}, default: []
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create index(:archives, [:link_id, :state])
    create unique_index(:archives, [:job_id])

    alter table(:snapshots) do
      add :archive_id, references(:archives, on_delete: :nilify_all)
    end

    create index(:snapshots, [:archive_id])
  end
end
