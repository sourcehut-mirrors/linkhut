defmodule Linkhut.Oauth.AccessGrant do
  use Ecto.Schema
  use ExOauth2Provider.AccessGrants.AccessGrant, otp_app: :linkhut

  schema "oauth_access_grants" do
    access_grant_fields()

    timestamps()
  end
end
