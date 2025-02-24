defmodule Linkhut.Repo.Migrations.UpdateUserIdxImportsTable do
  use Ecto.Migration

  def change do
    create unique_index(:imports, [:user_id])
  end
end
