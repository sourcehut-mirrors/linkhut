defmodule Linkhut.Repo.Migrations.CredentialsDropEmailConfirmationTokenAndUnconfirmedEmail do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      remove :email_confirmation_token
      remove :unconfirmed_email
    end
  end
end
