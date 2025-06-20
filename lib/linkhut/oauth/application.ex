defmodule Linkhut.Oauth.Application do
  use Ecto.Schema
  use ExOauth2Provider.Applications.Application, otp_app: :linkhut

  alias ExOauth2Provider.Applications

  @type t :: Ecto.Schema.t()

  schema "oauth_applications" do
    application_fields()

    timestamps()
  end

  def changeset(application, params) do
    Applications.Application.changeset(application, params, otp_app: :linkhut)
    |> Ecto.Changeset.validate_length(:name, max: 128)
  end
end
