defmodule Linkhut.Accounts.User do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.Credential
  alias Linkhut.Links.Link

  @type t :: Ecto.Schema.t()

  @username_format ~r/^[a-zA-Z\d]{3,}$/

  schema "users" do
    field :username, :string
    field :bio, :string
    field :unlisted, :boolean, default: false

    field :type, Ecto.Enum,
      values: [:unconfirmed, :active_free, :active_paying],
      default: :unconfirmed

    field :roles, {:array, Ecto.Enum}, values: [:admin], default: []
    has_one :credential, Credential

    has_many :links, Link, references: :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :bio])
    |> validate_required([:username])
    |> unique_constraint(:username)
    |> validate_format(:username, @username_format)
    |> validate_change(:username, fn :username, username ->
      if Linkhut.Reserved.valid_username?(username) do
        []
      else
        [username: ~s('#{username}' is reserved)]
      end
    end)
  end

  @spec changeset_role(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset_role(user, attrs) do
    user
    |> cast(attrs, [:roles])
    |> validate_subset(:roles, ~w(admin)a)
  end

  @spec confirm_user(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def confirm_user(%{credential: credential} = user, attrs) do
    user
    |> cast(attrs, [])
    |> put_assoc(:credential, Credential.confirm_email_changeset(credential, attrs),
      on_replace: :update
    )
    |> put_change(:type, :active_free)
  end
end
