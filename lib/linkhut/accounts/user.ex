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
    field :type, :string, default: "user"
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
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, ~w(user admin))
  end
end
