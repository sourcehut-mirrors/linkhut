defmodule Linkhut.Accounts.User do
  @moduledoc """
  The User schema represents a user account in the Linkhut application.

  A user can have different account types (unconfirmed, active_free, active_paying)
  and optional admin roles. Each user has an associated credential for authentication,
  can own multiple links, and participates in the OAuth system through applications,
  access grants, and access tokens.

  ## Schema Fields

  - `username` - Unique identifier for the user; must be alphanumeric and at least 3 characters
  - `bio` - Optional information about the user
  - `unlisted` - Boolean flag to hide the user's links from public listings
  - `type` - Account status enum: `:unconfirmed`, `:active_free`, or `:active_paying`
  - `roles` - Array of user roles, currently supports `:admin`

  ## Associations

  - `credential` - One-to-one association with user authentication credentials
  - `links` - One-to-many association with user's saved links
  - `applications` - One-to-many association with OAuth applications owned by the user
  - `access_grants` - One-to-many association with OAuth access grants
  - `access_tokens` - One-to-many association with OAuth access tokens

  ## Virtual Fields

  - `authenticated_at` - Timestamp of last authentication (virtual field)

  ## Examples

      iex> changeset = User.changeset(%User{}, %{username: "johndoe", bio: "Hello world"})
      iex> changeset.valid?
      true

      iex> User.confirm_user(%User{credential: %Credential{}}, %{})
      %Ecto.Changeset{changes: %{type: :active_free}}
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.Credential
  alias Linkhut.Moderation.Entry
  alias Linkhut.Links.Link

  @type t :: Ecto.Schema.t()

  schema "users" do
    field :username, :string
    field :bio, :string
    field :unlisted, :boolean, default: false
    field :is_banned, :boolean, default: false

    field :type, Ecto.Enum,
      values: [:unconfirmed, :active_free, :active_paying],
      default: :unconfirmed

    field :roles, {:array, Ecto.Enum}, values: [:admin], default: []
    has_one :credential, Credential, on_replace: :update
    has_many :moderation_entries, Entry, references: :id

    has_many :links, Link, references: :id, on_delete: :delete_all

    has_many :applications, Linkhut.Oauth.Application, foreign_key: :owner_id, references: :id

    has_many :access_grants, Linkhut.Oauth.AccessGrant,
      foreign_key: :resource_owner_id,
      references: :id,
      on_delete: :delete_all

    has_many :access_tokens, Linkhut.Oauth.AccessToken,
      foreign_key: :resource_owner_id,
      references: :id,
      on_delete: :delete_all

    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for updating user profile information.

  Validates the username format and ensures it's not reserved.

  ## Parameters

  - `user` - The user struct or changeset to update
  - `attrs` - Map of attributes to update (username, bio)

  ## Returns

  An `Ecto.Changeset` with the validated changes.

  ## Examples

      iex> User.changeset(%User{}, %{username: "validuser", bio: "My bio"})
      %Ecto.Changeset{valid?: true}

      iex> User.changeset(%User{}, %{username: "ab"})
      %Ecto.Changeset{valid?: false, errors: [username: {"...", [...]}]}
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :bio])
    |> validate_username()
  end

  @doc """
  Creates a changeset for updating user roles.

  ## Parameters

  - `user` - The user struct or changeset to update
  - `attrs` - Map containing the roles to set

  ## Returns

  An `Ecto.Changeset` with validated role changes.

  ## Examples

      iex> User.changeset_role(%User{}, %{roles: [:admin]})
      %Ecto.Changeset{valid?: true}

      iex> User.changeset_role(%User{}, %{roles: [:invalid]})
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset_role(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset_role(user, attrs) do
    user
    |> cast(attrs, [:roles])
    |> validate_subset(:roles, ~w(admin)a)
  end

  @doc """
  Creates a changeset to confirm a user's email and activate their account.

  This function confirms the user's email credential and upgrades their
  account type from `:unconfirmed` to `:active_free`.

  ## Parameters

  - `user` - User struct with associated credential
  - `attrs` - Attributes for email confirmation

  ## Returns

  An `Ecto.Changeset` that confirms the credential and updates user type.

  ## Examples

      iex> user = %User{credential: %Credential{}}
      iex> User.confirm_user(user, %{})
      %Ecto.Changeset{changes: %{type: :active_free}}
  """
  @spec confirm_user(Ecto.Schema.t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def confirm_user(%{credential: credential} = user, attrs) do
    user
    |> cast(attrs, [])
    |> put_assoc(:credential, Credential.confirm_email_changeset(credential, attrs),
      on_replace: :update
    )
    |> put_change(:type, :active_free)
  end

  def ban_user(user), do: change(user, %{is_banned: true})

  def unban_user(user), do: change(user, %{is_banned: false})

  # Helpers

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> unique_constraint(:username)
    |> validate_format(:username, ~r/^[a-zA-Z\d]{3,}$/)
    |> validate_change(:username, fn :username, username ->
      if Linkhut.Reserved.valid_username?(username) do
        []
      else
        [username: ~s('#{username}' is reserved)]
      end
    end)
  end
end
