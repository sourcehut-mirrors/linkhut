defmodule Linkhut.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Repo

  alias Linkhut.Accounts.{Credential, User}

  @typedoc """
  A username.

  The types `Accounts.username()` and `binary()` are equivalent to analysis tools.
  Although, for those reading the documentation, `Accounts.username()` implies a username.
  """
  @type username :: binary

  @typedoc """
  An `Ecto.Changeset` struct for the given `data_type`.
  """
  @type changeset(data_type) :: Ecto.Changeset.t(data_type)

  @doc """
  Gets a single user by its username or user id.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(integer) :: User.t()
  def get_user!(id) when is_number(id) do
    User
    |> Repo.get!(id)
  end

  @spec get_user!(username) :: User.t()
  def get_user!(username) when is_binary(username) do
    User
    |> Repo.get_by!(username: username)
  end

  @doc """
  Gets a single user by its username or user id.

  Returns `nil` if the User doesn't exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      nil

  """
  @spec get_user(integer) :: User.t() | nil
  def get_user(id) when is_number(id) do
    User
    |> Repo.get(id)
  end

  @spec get_user(username) :: User.t() | nil
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
  @spec create_user(%{optional(any) => any}) :: {:ok, User.t()} | {:error, changeset(User.t())}
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
  @spec update_user(User.t(), %{optional(any) => any}) ::
          {:ok, User.t()} | {:error, changeset(User.t())}
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
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, changeset(User.t())}
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user(User.t(), %{optional(any) => any}) :: changeset(User.t())
  def change_user(%User{} = user, attrs \\ %{}) do
    user
    |> Repo.preload(:credential)
    |> User.changeset(attrs)
  end

  @doc """
  Promotes an existing user to admin.

  ## Examples

      iex> set_admin_role(user)
      {:ok, %User{}}

  """
  @spec set_admin_role(User.t()) :: {:ok, User.t()} | {:error, changeset(User.t())}
  def set_admin_role(user) do
    user
    |> User.changeset_role(%{role: "admin"})
    |> Repo.update()
  end

  @spec is_admin?(User.t()) :: boolean()
  def is_admin?(%{type: "admin"}), do: true
  def is_admin?(_any), do: false

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
  Gets a single user by username and verifies the given password matches the stored hash.

  ## Examples

      iex> authenticate_by_username_password("user@example.com", "123456")
      {:ok, %User{}}

      iex> authenticate_by_username_password("user@example.com", "bad_password")
      {:error, :unauthorized}

  """
  def authenticate_by_username_password(username, password) do
    username
    |> get_user()
    |> Repo.preload(:credential)
    |> verify_password(password)
  end

  defp verify_password(nil, password) do
    no_user_verify(password: password)

    {:error, :unauthorized}
  end

  defp verify_password(%User{credential: %{password_hash: hash}} = user, password) do
    case verify_pass(password, hash) do
      true -> {:ok, user}
      false -> {:error, :unauthorized}
    end
  end
end
