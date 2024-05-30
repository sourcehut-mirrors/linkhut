defmodule Linkhut.Accounts.Credential do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Ecto.Changeset
  alias Linkhut.Accounts.User

  @email_format ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  schema "credentials" do
    field :email, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :email_confirmed_at, :utc_datetime
    field :email_confirmation_token, :string
    field :unconfirmed_email, :string
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> unique_constraint(:email)
    |> validate_format(:email, @email_format)
    |> email_confirmation(attrs)
  end

  @doc false
  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_length(:password, min: 6)
    |> put_password_hash
  end

  @doc """
  Sets the e-mail as confirmed.

  This updates `:email_confirmed_at` and sets `:email_confirmation_token` to
  nil.

  If the struct has a `:unconfirmed_email` value, then the `:email` will be
  changed to this value, and `:unconfirmed_email` will be set to nil.
  """
  @spec confirm_email_changeset(Ecto.Schema.t() | Changeset.t(), map()) :: Changeset.t()
  def confirm_email_changeset(
        %Changeset{data: %{unconfirmed_email: unconfirmed_email}} = changeset,
        params
      )
      when not is_nil(unconfirmed_email) do
    confirm_email(changeset, unconfirmed_email, params)
  end

  def confirm_email_changeset(
        %Changeset{data: %{email_confirmed_at: nil, email: email}} = changeset,
        params
      ) do
    confirm_email(changeset, email, params)
  end

  def confirm_email_changeset(%Changeset{} = changeset, _params), do: changeset

  def confirm_email_changeset(%__MODULE__{} = credential, params) do
    credential
    |> Changeset.change()
    |> confirm_email_changeset(params)
  end

  defp confirm_email(changeset, email, _params) do
    confirmed_at = DateTime.utc_now(:second)

    changes =
      [
        email_confirmed_at: confirmed_at,
        email: email,
        unconfirmed_email: nil,
        email_confirmation_token: nil
      ]

    changeset
    |> Changeset.change(changes)
    |> Changeset.unique_constraint(:email)
  end

  @doc false
  def changeset_email_verification(credential, attrs) do
    credential
    |> cast(attrs, [:email_confirmed_at])
  end

  @spec changeset(Changeset.t(), map()) :: Changeset.t()
  defp email_confirmation(%{valid?: true} = changeset, attrs) do
    cond do
      built?(changeset) ->
        put_email_confirmation_token(changeset)

      email_reverted?(changeset, attrs) ->
        changeset
        |> Changeset.put_change(:email_confirmation_token, nil)
        |> Changeset.put_change(:unconfirmed_email, nil)

      email_changed?(changeset) ->
        current_email = changeset.data.email
        changed_email = Changeset.get_field(changeset, :email)
        changeset = set_unconfirmed_email(changeset, current_email, changed_email)

        case unconfirmed_email_changed?(changeset) do
          true -> put_email_confirmation_token(changeset)
          false -> changeset
        end

      true ->
        changeset
    end
  end

  defp email_confirmation(changeset, _attrs), do: changeset

  defp built?(changeset), do: Ecto.get_meta(changeset.data, :state) == :built

  defp email_reverted?(changeset, attrs) do
    param = Map.get(attrs, :email) || Map.get(attrs, "email")
    current = changeset.data.email

    param == current
  end

  defp email_changed?(changeset) do
    case Changeset.get_change(changeset, :email) do
      nil -> false
      _any -> true
    end
  end

  def put_email_confirmation_token(changeset) do
    changeset
    |> Changeset.put_change(
      :email_confirmation_token,
      :crypto.strong_rand_bytes(16) |> :base64.encode()
    )
    |> Changeset.unique_constraint(:email_confirmation_token)
  end

  defp set_unconfirmed_email(changeset, current_email, new_email) do
    changeset
    |> Changeset.put_change(:email, current_email)
    |> Changeset.put_change(:unconfirmed_email, new_email)
  end

  defp unconfirmed_email_changed?(changeset) do
    case Changeset.get_change(changeset, :unconfirmed_email) do
      nil -> false
      _any -> true
    end
  end

  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       ) do
    put_change(
      changeset,
      :password_hash,
      Argon2.hash_pwd_salt(password)
    )
  end

  defp put_password_hash(changeset), do: changeset
end
