defmodule Linkhut.Oauth do
  @moduledoc false

  import Ecto.Query
  alias Linkhut.Repo

  alias Linkhut.Accounts.User
  alias Linkhut.Oauth.AccessToken
  alias Linkhut.Oauth.Application
  alias ExOauth2Provider.AccessTokens
  alias ExOauth2Provider.Applications
  alias ExOauth2Provider.Authorization
  alias ExOauth2Provider.Authorization.Utils.Response
  alias ExOauth2Provider.Utils

  @doc """
  Creates an access token.

  ## Examples

      iex> create_token(resource_owner, %{application: application, scopes: "read write"})
      {:ok, %AccessToken{}}

      iex> create_token(resource_owner, %{scopes: "read write"})
      {:ok, %AccessToken{}}

      iex> create_token(resource_owner, %{expires_in: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_token!(User.t(), String.t()) :: AccessToken.t()
  def create_token!(user, attrs) do
    case create_token(user, attrs) do
      {:ok, token} -> token
      {:error, changeset} -> raise "Error creating token: #{inspect(changeset)}"
    end
  end

  defp create_token(resource_owner, attrs) do
    %AccessToken{}
    |> Map.put(:scopes, (for scope <- ~w(posts tags), access <- ~w(read write), do: "#{scope}:#{access}") |> Enum.join(" "))
    |> Map.put(:resource_owner, resource_owner)
    |> put_application(attrs)
    |> do_create_token(attrs)
  end

  defp put_application(access_token, attrs) do
    case Map.get(attrs, :application) do
      nil -> access_token
      application -> %{access_token | application: application}
    end
  end

  defp do_create_token(access_token, attrs) do
    attrs =
      Map.merge(%{expires_in: Timex.Duration.to_seconds(365, :days)}, attrs)

    access_token
    |> AccessToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the personal access token associated with this id
  """
  @spec get_token!(User.t(), integer) :: AccessToken.t()
  def get_token!(user, id) do
    from(t in AccessToken,
      where: t.id == ^id and t.resource_owner_id == ^user.id and is_nil(t.revoked_at)
    )
    |> Repo.one!()
    |> Repo.preload([:application, :resource_owner])
  end

  @doc """
  Gets all personal access tokens for a given user
  """
  @spec get_tokens(User.t()) :: [AccessToken.t()]
  def get_tokens(user) do
    AccessTokens.get_authorized_tokens_for(user, otp_app: :linkhut)
    |> Enum.filter(fn %{application_id: id} -> id == nil end)
    |> Enum.filter(fn token -> !AccessTokens.is_revoked?(token) end)
  end

  @doc """
  Returns a changeset corresponding to the given token
  """
  @spec change_token(AccessToken.t()) :: Ecto.Changeset.t()
  def change_token(token) do
    token
    |> AccessToken.changeset()
  end

  @doc """
  Revoke the provided token
  """
  @spec revoke!(AccessToken.t()) :: AccessToken.t()
  def revoke!(token) do
    AccessTokens.revoke!(token, otp_app: :linkhut)
  end

  @doc """
  Create application changeset.

  ## Examples

      iex> change_application(application, %{})
      {:ok, %Application{}}

  """
  @spec change_application(Application.t(), map()) :: Changeset.t()
  def change_application(%Application{} = application, params \\ %{}) do
    application
    |> Application.changeset(params)
  end

  @doc """
  Creates an application.

  ## Examples

      iex> create_application(user, %{name: "App", redirect_uri: "http://example.com"})
      {:ok, %Application{}}

      iex> create_application(user, %{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_application(User.t(), map()) :: {:ok, Application.t()} | {:error, Changeset.t()}
  def create_application(%User{} = user, params) do
    user
    |> Applications.create_application(params, otp_app: :linkhut)
  end

  @doc """
  Returns all applications for a owner.

  ## Examples

      iex> get_applications_for(user)
      [%Application{}, ...]

  """
  @spec get_applications_for(User.t()) :: [Application.t()]
  def get_applications_for(%User{} = user) do
    user
    |> Applications.get_applications_for(otp_app: :linkhut)
    |> Repo.preload(access_tokens: AccessToken.active())
  end

  @doc """
  Gets a single application for a user.

  Raises `Ecto.NoResultsError` if the Application does not exist for the given user.

  ## Examples

      iex> get_application_for!(user, "c341a5c7b331ef076eb4954668d54f590e0009e06b81b100191aa22c93044f3d")
      %Application{}

      iex> get_application_for!(user, "75d72f326a69444a9287ea264617058dbbfe754d7071b8eef8294cbf4e7e0fdc")
      ** (Ecto.NoResultsError)

  """
  @spec get_application_for!(User.t(), binary()) :: Application.t() | no_return
  def get_application_for!(user, uid) do
    user
    |> Applications.get_application_for!(uid, otp_app: :linkhut)
  end

  def reset_secret(application) do
    application
    |> update_application(%{secret: Utils.generate_token()})
  end

  @doc """
  Updates an application.

  ## Examples

      iex> update_application(application, %{name: "Updated App"})
      {:ok, %Application{}}

      iex> update_application(application, %{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_application(Application.t(), map()) ::
          {:ok, Application.t()} | {:error, Changeset.t()}
  def update_application(application, attrs) do
    application
    |> Application.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Check ExOauth2Provider.Authorization.Code for usage.
  """
  @spec preauthorize(User.t(), map()) ::
          Response.success() | Response.error() | Response.redirect() | Response.native_redirect()
  def preauthorize(user, params) do
    case Authorization.preauthorize(user, params, otp_app: :linkhut) do
      {:ok, client, scopes} -> {:ok, client |> Repo.preload(:owner), scopes}
      response -> response
    end
  end

  @doc """
  Check ExOauth2Provider.Authorization.Code for usage.
  """
  @spec authorize(User.t(), map()) ::
          {:ok, binary()} | Response.error() | Response.redirect() | Response.native_redirect()
  def authorize(user, params) do
    Authorization.authorize(user, params, otp_app: :linkhut)
  end

  @doc """
  Check ExOauth2Provider.Authorization.Code for usage.
  """
  @spec deny(User.t(), map()) :: Response.error() | Response.redirect()
  def deny(user, params) do
    Authorization.deny(user, params, otp_app: :linkhut)
  end

  @doc """
  Gets all authorized applications for a user.

  ## Examples

      iex> get_authorized_applications_for(user)
      [%Application{},...]

  """
  @spec get_authorized_applications_for(User.t()) :: [Application.t()]
  def get_authorized_applications_for(user) do
    Applications.get_authorized_applications_for(user, otp_app: :linkhut)
    |> Repo.preload([:owner, access_tokens: from(t in AccessToken, order_by: t.inserted_at)])
  end

  @doc """
  Deletes an application.

  ## Examples

      iex> delete_application(application)
      {:ok, %Application{}}

      iex> delete_application(application)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_application(Application.t()) :: {:ok, Application.t()} | {:error, Changeset.t()}
  def delete_application(application) do
    Applications.delete_application(application, otp_app: :linkhut)
  end

  @doc """
  Revokes all access tokens for an application and user.

  ## Examples

      iex> revoke_all_access_tokens_for(application, user)
      {:ok, [%AccessToken{}]}

  """
  @spec revoke_all_access_tokens_for(Application.t(), User.t()) :: [AccessToken.t()]
  def revoke_all_access_tokens_for(application, user) do
    Applications.revoke_all_access_tokens_for(application, user, otp_app: :linkhut)
  end
end
