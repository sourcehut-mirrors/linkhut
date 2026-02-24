defmodule Linkhut.Repo.Migrations.AddUserIdToSnapshots do
  use Ecto.Migration

  def change do
    alter table(:snapshots) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:snapshots, [:user_id])

    execute(
      "UPDATE snapshots SET user_id = links.user_id FROM links WHERE snapshots.link_id = links.id",
      "SELECT 1"
    )
  end
end
