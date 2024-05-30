defmodule Linkhut.Repo.Migrations.EmailVerification do
  use Ecto.Migration

  def change do
    alter table("credentials") do
      add :email_confirmed_at, :utc_datetime, default: nil
      add :email_confirmation_token, :string, default: nil
      add :unconfirmed_email, :string, default: nil
    end

    create index(:credentials, [:email_confirmation_token])
  end
end
