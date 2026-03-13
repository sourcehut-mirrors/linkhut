defmodule Linkhut.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :timezone, :string
      add :show_url, :boolean, null: false, default: true
      add :show_exact_dates, :boolean, null: false, default: false
      add :default_private, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_preferences, [:user_id])
  end
end
