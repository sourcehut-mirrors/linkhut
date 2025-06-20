defmodule Linkhut.Moderation do
  @moduledoc """
  The Moderation context.
  """

  import Ecto.Query

  alias Linkhut.Repo

  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Moderation.Entry

  @doc """
  Bans a user with an optional reason.

  ## Examples

      iex> ban_user(username, "Spam posting")
      {:ok, %User{}}

      iex> ban_user(username, nil)
      {:ok, %User{}}

  """
  def ban_user(username, reason \\ nil) do
    with %User{} = user <- Accounts.get_user(username),
         %Ecto.Changeset{} = ban <- Entry.ban_changeset(user, %{reason: reason}) do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:user, User.ban_user(user))
      |> Ecto.Multi.insert(:ban, ban)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, :ban, changeset, _} -> {:error, changeset}
        {:error, :user, changeset, _} -> {:error, changeset}
      end
    else
      %Ecto.Changeset{} = changeset ->
        {:error, changeset}

      nil ->
        %Ecto.Changeset{} |> Ecto.Changeset.add_error(:username, "No user matching this username")
    end
  end

  @doc """
  Unbans a user.

  ## Examples

      iex> unban_user(user)
      {:ok, %User{}}

  """
  def unban_user(username) do
    with %User{} = user <- Accounts.get_user(username),
         %Ecto.Changeset{} = unban <- Entry.unban_changeset(user) do
      Ecto.Multi.new()
      |> Ecto.Multi.update(:user, User.unban_user(user))
      |> Ecto.Multi.insert(:unban, unban)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, :unban, changeset, _} -> {:error, changeset}
        {:error, :user, changeset, _} -> {:error, changeset}
      end
    else
      %Ecto.Changeset{} = changeset ->
        {:error, changeset}

      nil ->
        %Ecto.Changeset{} |> Ecto.Changeset.add_error(:username, "No user matching this username")
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
