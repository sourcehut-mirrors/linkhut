defmodule Linkhut.Repo.Migrations.ChangeImportsStateDefaultToQueued do
  use Ecto.Migration

  def up do
    alter table(:imports) do
      modify :state, :string, default: "queued"
    end
  end

  def down do
    alter table(:imports) do
      modify :state, :string, default: "in_progress"
    end
  end
end
