defmodule Linkhut.Repo.Migrations.UpdateLinksIndices do
  use Ecto.Migration

  def change do
    create index(:links, [:inserted_at])
  end
end
