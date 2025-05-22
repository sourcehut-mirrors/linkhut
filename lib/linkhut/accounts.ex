defmodule Linkhut.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query

  import Argon2, only: [verify_pass: 2, no_user_verify: 1]
  alias Linkhut.Repo

  alias Linkhut.Accounts.{Credential, User, UserToken, UserNotifier}

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
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(binary) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    from(u in User,
      join: c in assoc(u, :credential),
      where: fragment("lower(?)", c.email) == ^String.downcase(email)
    )
    |> Repo.one()
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
  Updates a user profile.

  ## Examples

      iex> update_profile(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_profile(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_profile(User.t(), %{optional(any) => any}) ::
          {:ok, User.t()} | {:error, changeset(User.t())}
  def update_profile(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user, %{"confirmed" => "true"})
      {:ok, %User{}}

      iex> delete_user(user, %{})
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user(changeset(User.t()), %{any() => any()}) ::
          {:ok, User.t()} | {:error, changeset(User.t())}
  def delete_user(%User{} = user, attrs) do
    user
    |> Repo.preload(:credential)
    |> User.changeset(attrs)
    |> Ecto.Changeset.validate_acceptance(:confirmed,
      message: "Please confirm you want to delete your account"
    )
    |> Ecto.Changeset.no_assoc_constraint(:applications,
      message:
        "You still own OAuth applications, you must delete those before deleting your account"
    )
    |> Repo.delete()
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
    |> Ecto.Changeset.cast_assoc(:credential,
      with: &Credential.email_changeset(&1, &2, validate_email: false)
    )
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
  Returns the email of a given user.

  ## Examples

      iex> get_email(user)
      "foo@example.com"

  """
  @spec get_email(User.t()) :: String.t()
  def get_email(%User{} = user) do
    user
    |> Repo.preload(:credential)
    |> get_in([Access.key(:credential), Access.key(:email)])
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

      iex> authenticate_by_username_password("username", "123456")
      {:ok, %User{}}

      iex> authenticate_by_username_password("username", "bad_password")
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
          email_confirmed_at: timestamp
        }
      })
      when is_nil(timestamp),
      do: true

  def current_email_unconfirmed?(_user),
    do: false

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_email(user, token) do
    user = Repo.preload(user, :credential)
    context = "change:#{user.credential.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp email_multi(user, email, context) do
    changeset =
      user.credential
      |> Credential.confirm_email_changeset(%{"email" => email})

    Ecto.Multi.new()
    |> Ecto.Multi.update(:credential, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_update_email_instructions(user, current_email, &url(~p"/_/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(%User{} = user, current_email, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    if current_email != user.credential.email do
      Repo.insert!(user_token)
      UserNotifier.deliver_update_email_instructions(user, confirmation_url_fun.(encoded_token))
    else
      {:error, :already_confirmed}
    end
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_email_change(user, %{"credential" => %{"email" => email}})
      {:ok, %User{}, "current@example.com"}

      iex> apply_email_change(user, %{"credential" => %{"email" => email}})
      {:error, %Ecto.Changeset{}}

  """
  def apply_email_change(user, params) do
    with %{"credential" => %{"email" => email}} <- params,
         %User{credential: %Credential{} = c} = user <- Repo.preload(user, :credential),
         true <- c.email != email do
      case user
           |> User.changeset(Map.take(params, ["credential"]))
           |> Ecto.Changeset.cast_assoc(:credential, with: &Credential.email_changeset/2)
           |> Ecto.Changeset.apply_action(:update) do
        {:ok, user} -> {:ok, user, c.email}
        {:error, changeset} -> {:error, changeset}
      end
    else
      _ -> {:ok, user}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_email_confirmation_instructions(user, &url(~p"/_/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_email_confirmation_instructions(confirmed_user, &url(~p"/_/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_email_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    user = Repo.preload(user, :credential)

    if user.credential.email_confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(%User{id: user_id} = _user, token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{id: id} = user when id == user_id <- Repo.one(query) |> Repo.preload(:credential),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_user(user, %{}))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_reset_password_instructions(user, &url(~p"/users/reset-password/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    user = Repo.preload(user, :credential)
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) |> Repo.preload(:credential) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:credential, Credential.registration_changeset(user.credential, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{credential: credential}} -> {:ok, credential}
      {:error, :credential, changeset, _} -> {:error, changeset}
    end
  end
end
