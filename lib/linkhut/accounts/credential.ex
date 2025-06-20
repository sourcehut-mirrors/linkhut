defmodule Linkhut.Accounts.Credential do
  @moduledoc """
  Manages user authentication credentials including email and password handling.

  This module defines the `Credential` schema and provides functions for creating,
  updating, and validating user credentials.

  ## Schema Fields

  - `:email` - User's email address (string, max 160 characters)
  - `:password` - Virtual field for password input (not persisted, redacted)
  - `:password_hash` - Hashed password stored in database
  - `:email_confirmed_at` - Timestamp when email was confirmed (UTC datetime)
  - `:user` - Belongs to association with User schema

  ## Usage Examples

      # Create a registration changeset
      attrs = %{email: "user@example.com", password: "secure123"}
      changeset = Credential.registration_changeset(%Credential{}, attrs)

      # Change email address
      changeset = Credential.email_changeset(credential, %{email: "new@example.com"})

      # Confirm email address
      changeset = Credential.confirm_email_changeset(credential, %{email: "confirmed@example.com"})
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Ecto.Changeset
  alias Linkhut.Accounts.User

  schema "credentials" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string
    field :email_confirmed_at, :utc_datetime
    belongs_to :user, User

    timestamps()
  end

  @doc """
  Creates a changeset for updating credentials without email validation.

  This is typically used for updating an existing credential so email uniqueness
  checking is not required.

  ## Parameters

  - `credential` - The credential struct to update
  - `attrs` - Map of attributes to change

  ## Returns

  An `Ecto.Changeset` with email validation disabled.
  """
  @spec changeset(Ecto.Schema.t(), map()) :: Changeset.t()
  def changeset(credential, attrs) do
    email_changeset(credential, attrs, validate_email: false)
  end

  @doc """
  Creates a changeset for user registration with full validation.

  Validates both email and password fields with all constraints enabled.
  This should be used when creating new user accounts.

  ## Parameters

  - `credential` - The credential struct (typically empty)
  - `attrs` - Map containing `:email` and `:password` keys

  ## Returns

  An `Ecto.Changeset` with complete validation for new registrations.

  ## Example

      attrs = %{email: "user@example.com", password: "securepass123"}
      changeset = Credential.registration_changeset(%Credential{}, attrs)
  """
  @spec registration_changeset(Ecto.Schema.t(), map()) :: Changeset.t()
  def registration_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:email, :password])
    |> validate_email(validate_email: true)
    |> validate_password()
  end

  @doc """
  A credential changeset for changing the email.

  It requires the email to change, otherwise an error is added.

  ## Parameters

  - `credential` - The existing credential struct
  - `attrs` - Map containing the new email
  - `opts` - Keyword list of options (optional)
    - `:validate_email` - Whether to validate email uniqueness (default: true)

  ## Returns

  An `Ecto.Changeset` for updating the email field.
  """
  @spec email_changeset(Ecto.Schema.t(), map(), keyword()) :: Changeset.t()
  def email_changeset(credential, attrs, opts \\ []) do
    credential
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_length(:email, max: 160)
    |> validate_format(
      :email,
      ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
    )
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 6, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> put_password_hash()
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Linkhut.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  Updates the e-mail and marks it as confirmed.

  This updates `:email_confirmed_at` to the current UTC timestamp and
  validates the new email address.

  ## Parameters

  - `credential` - The credential struct to update
  - `attrs` - Map containing the confirmed email address

  ## Returns

  An `Ecto.Changeset` with the email confirmed and timestamp set.

  ## Example

      changeset = Credential.confirm_email_changeset(credential, %{email: "confirmed@example.com"})
  """
  @spec confirm_email_changeset(Ecto.Schema.t(), map()) :: Changeset.t()
  def confirm_email_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:email])
    |> validate_email(validate_email: true)
    |> put_change(:email_confirmed_at, DateTime.utc_now(:second))
  end

  defp put_password_hash(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(
        :password_hash,
        Argon2.hash_pwd_salt(password)
      )
      |> delete_change(:password)
    else
      changeset
    end
  end
end
