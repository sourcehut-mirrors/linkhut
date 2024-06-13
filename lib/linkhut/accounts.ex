defmodule Linkhut.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query

  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Repo

  alias Linkhut.Accounts.{Credential, EmailToken, User, UserNotifier}

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
    |> User.changeset_role(%{roles: [:admin]})
    |> Repo.update()
  end

  @spec is_admin?(User.t()) :: boolean()
  def is_admin?(%User{roles: roles}), do: Enum.any?(roles, fn r -> r == :admin end)
  def is_admin?(_), do: false

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

  @doc """
  Finds a user by the `email_confirmation_token` column.
  """
  @spec get_by_confirmation_token(binary()) :: Context.user() | nil
  def get_by_confirmation_token(token) do
    User
    |> join(:left, [u], c in Credential, on: u.id == c.user_id)
    |> where([_, c], c.email_confirmation_token == ^token)
    |> Repo.one()
    |> Repo.preload(:credential)
  end

  @doc """
  Checks if the users current e-mail is unconfirmed.
  """
  @spec current_email_unconfirmed?(Context.user()) :: boolean()
  def current_email_unconfirmed?(%{credential: %Ecto.Association.NotLoaded{}} = user) do
    user
    |> Repo.preload(:credential)
    |> current_email_unconfirmed?()
  end

  def current_email_unconfirmed?(%{
        credential: %{
          unconfirmed_email: nil,
          email_confirmation_token: token,
          email_confirmed_at: nil
        }
      })
      when not is_nil(token),
      do: true

  def current_email_unconfirmed?(_user),
    do: false

  @doc """
  Checks if the user has a pending e-mail change.
  """
  @spec pending_email_change?(Context.user()) :: boolean()
  def pending_email_change?(%{credential: %Ecto.Association.NotLoaded{}} = user) do
    user
    |> Repo.preload(:credential)
    |> pending_email_change?()
  end

  def pending_email_change?(%{
        credential: %{unconfirmed_email: email, email_confirmation_token: token}
      })
      when not is_nil(email) and not is_nil(token),
      do: true

  def pending_email_change?(_user), do: false

  def deliver_email_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    user = Repo.preload(user, :credential)

    if current_email_unconfirmed?(user) != nil do
      token = EmailToken.new(user.credential, "confirm")
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(token))
    else
      {:error, :already_confirmed}
    end
  end

  def deliver_update_email_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    user = Repo.preload(user, :credential)

    if pending_email_change?(user) != nil do
      token = EmailToken.new(user.credential, "confirm")
      UserNotifier.deliver_update_email_instructions(user, confirmation_url_fun.(token))
    else
      {:error, :already_confirmed}
    end
  end

  def confirm_email(user, token) do
    case EmailToken.verify(token, "confirm") do
      {:ok, token} -> validate_email_confirmation(user, token)
      _ -> :error
    end
  end

  defp validate_email_confirmation(user, token) do
    case get_by_confirmation_token(token) do
      %User{id: id, credential: _credential} = unverified_user when id == user.id ->
        mark_as_verified(unverified_user)

      _ ->
        :error
    end
  end

  defp mark_as_verified(%User{credential: _credential} = user) do
    user
    |> User.confirm_user(%{})
    |> Repo.update()
  end
end
