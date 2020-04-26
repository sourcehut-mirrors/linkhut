defmodule Linkhut.Model.User do
  use Ecto.Schema
  import Ecto.Changeset

  @email_format ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
  @username_format ~r/^[a-zA-Z\d]{3,}$/

  schema "users" do
    field :username, :string
    field :email, :string
    field :bio, :string
    field :password, :string, virtual: true
    field :password_hash, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :bio])
    |> validate_required([:username, :email])
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> validate_format(:username, @username_format)
    |> validate_format(:email, @email_format)
  end

  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_length(:password, min: 6)
    |> put_password_hash
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
