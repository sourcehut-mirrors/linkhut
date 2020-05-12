defmodule Linkhut.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Repo

  alias Linkhut.Accounts.{Credential, User}

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id) when is_number(id) do
    User
    |> Repo.get!(id)
  end

  @doc """
  Gets a single user by its username

  Returns `nil` if no result was found

  ## Examples

      iex> get_user("foo")
      %User{}

      iex> get_user!("bar")
      nil

  """
  def get_user(username) when is_binary(username) do
    User
    |> Repo.get_by(username: username)
  end

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Ecto.Changeset.cast_assoc(:credential, with: &Credential.registration_changeset/2)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> Repo.preload(:credential)
    |> User.changeset(attrs)
    |> Ecto.Changeset.cast_assoc(:credential, with: &Credential.changeset/2)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    user
    |> Repo.preload(:credential)
    |> User.changeset(attrs)
  end

  @doc """
  Updates a credential.

  ## Examples

      iex> update_credential(credential, %{field: new_value})
      {:ok, %Credential{}}

      iex> update_credential(credential, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking credential changes.

  ## Examples

      iex> change_credential(credential)
      %Ecto.Changeset{data: %Credential{}}

  """
  def change_credential(%Credential{} = credential, attrs \\ %{}) do
    Credential.changeset(credential, attrs)
  end

  @doc """
  Gets a single user by username and verifies the given password matches the stored hash

  ## Examples

      iex> authenticate_by_username_password("user@example.com", "123456")
      {:ok, %User{}}

      iex> authenticate_by_username_password("user@example.com", "bad_password")
      {:error, :unauthorized}

  """
  def authenticate_by_username_password(username, password) do
    case get_user(username) do
      %User{} = user ->
        if verify_pass(password, user.credential.password_hash) do
          {:ok, user}
        else
          {:error, :unauthorized}
        end

      nil ->
        no_user_verify(password: password)
        {:error, :unauthorized}
    end
  end
end
