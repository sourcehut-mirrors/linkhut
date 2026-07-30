defmodule Linkhut.Repo.Migrations.ImportsAddFile do
  use Ecto.Migration

  def change do
    alter table(:imports) do
      add :file, :string
    end
  end
end
