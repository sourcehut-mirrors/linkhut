defmodule Linkhut.Repo.Migrations.AddBannedFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_banned, :boolean, default: false, null: false
    end

    create table(:moderation_entries) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :reason, :text
      add :action, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users, [:is_banned])
    create index(:moderation_entries, [:user_id])
  end
end
