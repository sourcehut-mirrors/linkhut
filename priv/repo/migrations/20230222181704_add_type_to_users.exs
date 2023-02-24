defmodule Linkhut.Repo.Migrations.AddTypeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :type, :string, default: "user", null: false
    end
  end
end
