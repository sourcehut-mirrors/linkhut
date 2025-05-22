defmodule Linkhut.Accounts.Credential do
  @moduledoc false

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

  @doc false
  def changeset(credential, attrs) do
    email_changeset(credential, attrs, validate_email: false)
  end

  @doc false
  def registration_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:email, :password])
    |> validate_email(validate_email: true)
    |> validate_password()
  end

  @doc """
  A credential changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
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

  This updates `:email_confirmed_at`.
  """
  @spec confirm_email_changeset(Ecto.Schema.t(), map()) :: Changeset.t()
  def confirm_email_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:email])
    |> validate_email(validate_email: true)
    |> changeset_email_verification(%{"email_confirmed_at" => DateTime.utc_now(:second)})
  end

  @doc false
  def changeset_email_verification(credential, attrs) do
    credential
    |> cast(attrs, [:email_confirmed_at])
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
