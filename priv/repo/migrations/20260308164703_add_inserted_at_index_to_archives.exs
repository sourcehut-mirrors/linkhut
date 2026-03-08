defmodule Linkhut.Repo.Migrations.AddInsertedAtIndexToArchives do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:archives, [:inserted_at], concurrently: true)
  end
end
