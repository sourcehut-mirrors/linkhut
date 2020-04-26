defmodule Linkhut.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links, primary_key: false) do
      add :url, :string, primary_key: true
      add :user_id, references(:users, on_delete: :nothing), primary_key: true
      add :title, :string
      add :notes, :text
      add :tags, {:array, :string}
      add :is_private, :boolean, default: false, null: false
      add :language, :string

      timestamps(type: :utc_datetime)
    end

    create index(:links, [:url])
    create index(:links, [:user_id])
    create index(:links, [:url, :user_id])
  end
end
