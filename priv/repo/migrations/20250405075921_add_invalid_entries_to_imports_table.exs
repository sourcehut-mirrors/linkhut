defmodule Linkhut.Repo.Migrations.AddInvalidEntriesToImportsTable do
  use Ecto.Migration

  def change do
    alter table(:imports) do
      add :invalid, :integer
      add :invalid_entries, {:array, :text}, default: []
    end
  end
end
