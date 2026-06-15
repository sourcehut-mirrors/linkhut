defmodule Linkhut.Repo.Migrations.UserPreferencesAddTheme do
  use Ecto.Migration

  def change do
    alter table(:user_preferences) do
      add :theme, :string
    end
  end
end
