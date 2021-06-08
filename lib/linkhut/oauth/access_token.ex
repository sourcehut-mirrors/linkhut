defmodule Linkhut.Oauth.AccessToken do
  use Ecto.Schema
  use ExOauth2Provider.AccessTokens.AccessToken, otp_app: :linkhut

  import Ecto.Query
  alias ExOauth2Provider.AccessTokens
  alias Linkhut.Oauth.AccessToken

  @type t :: Ecto.Schema.t()

  schema "oauth_access_tokens" do
    access_token_fields()

    # custom fields
    field :comment, :string, default: ""

    timestamps()
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(token, params \\ %{}) do
    token
    |> AccessTokens.AccessToken.changeset(params, otp_app: :linkhut)
    |> Ecto.Changeset.cast(params, [:comment])
    |> Ecto.Changeset.validate_length(:comment, max: 128)
  end

  @doc false
  def active() do
    from(t in AccessToken,
      where:
        is_nil(t.revoked_at) and
          datetime_add(t.inserted_at, t.expires_in, "second") > ^DateTime.now!("Etc/UTC")
    )
  end
end
