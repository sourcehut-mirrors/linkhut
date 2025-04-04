defmodule Linkhut.Repo.Migrations.AddOverridesToImportsTable do
  use Ecto.Migration

  def change do
    alter table("imports") do
      add :overrides, :map, default: %{}
    end
  end
end
