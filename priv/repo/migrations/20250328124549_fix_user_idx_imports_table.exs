defmodule Linkhut.Repo.Migrations.FixUserIdxImportsTable do
  use Ecto.Migration

  def change do
    drop unique_index(:imports, [:user_id])
    create index(:imports, [:user_id])
  end
end
