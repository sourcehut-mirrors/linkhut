defmodule Linkhut.Moderation do
  @moduledoc """
  The Moderation context.
  """

  import Ecto.Query

  alias Linkhut.Config
  alias Linkhut.Repo

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Moderation.Entry

  @doc """
  Returns the cutoff datetime for the account-age quarantine.

  Accounts created after this point are considered "new" and their content
  is hidden from public discovery surfaces (search, recent, popular).
  """
  @spec account_age_cutoff() :: DateTime.t()
  def account_age_cutoff do
    days = Config.moderation(:account_age_days, 30)
    DateTime.add(DateTime.utc_now(), -days, :day)
  end

  @doc """
  Bans a user with an optional reason.

  ## Examples

      iex> ban_user(username, "Spam posting")
      {:ok, %User{}}

      iex> ban_user(username, nil)
      {:ok, %User{}}

  """
  def ban_user(username, reason \\ nil) do
    user = Accounts.get_user(username)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.ban_user(user))
    |> Ecto.Multi.insert(:ban, fn %{user: user} ->
      Entry.ban_changeset(user, %{reason: reason})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Unbans a user.

  ## Examples

      iex> unban_user(username)
      {:ok, %User{}}

      iex> ban_user(username, "No longer spam posting")
      {:ok, %User{}}

  """
  def unban_user(username, reason \\ nil) do
    user = Accounts.get_user(username)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.unban_user(user))
    |> Ecto.Multi.insert(:ban, fn %{user: user} ->
      Entry.unban_changeset(user, %{reason: reason})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Gets all banned users.

  ## Examples

      iex> list_banned_users()
      [%User{}, ...]

  """
  def list_banned_users() do
    User
    |> where([u], u.is_banned == true)
    |> Repo.all()
    |> Repo.preload(:moderation_entries)
  end
end
