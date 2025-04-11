defmodule Linkhut.Repo.Migrations.AddEmailUniqueConstraint do
  use Ecto.Migration

  def change do
    drop unique_index(:credentials, :email)
    create unique_index(:credentials, ["(lower(email))"], name: :credentials_email_index)
  end
end
