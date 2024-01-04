defmodule Linkhut.Repo.Migrations.AddUnlistedToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :unlisted, :boolean, default: false, null: false
    end

    create index(:users, [:unlisted])
  end
end
