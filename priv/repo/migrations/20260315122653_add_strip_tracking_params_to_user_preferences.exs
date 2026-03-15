defmodule Linkhut.Repo.Migrations.AddStripTrackingParamsToUserPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_preferences) do
      add :strip_tracking_params, :boolean, null: false, default: false
    end
  end
end
