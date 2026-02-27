defmodule Linkhut.Repo.Migrations.CreateArchives do
  use Ecto.Migration

  def change do
    create table(:archives) do
      add :link_id, references(:links, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :nilify_all)
      add :url, :text
      add :final_url, :text
      add :state, :string, default: "pending", null: false
      add :preflight_meta, :map
      add :steps, {:array, :map}, default: []
      add :error, :text
      add :total_size_bytes, :bigint, default: 0, null: false
      add :lock_version, :integer, default: 0, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:archives, [:link_id, :state])

    alter table(:snapshots) do
      add :archive_id, references(:archives, on_delete: :nilify_all)
      add :crawler_meta, :map, null: false, default: fragment("'{}'::jsonb")
    end

    create index(:snapshots, [:archive_id])

    create index(:snapshots, [:state],
             where: "state = 'pending_deletion'",
             name: :snapshots_state_pending_deletion_index
           )
  end
end
