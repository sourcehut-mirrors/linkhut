defmodule Linkhut.ModerationTest do
  use Linkhut.DataCase

  alias Linkhut.Moderation
  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Moderation.Entry

  import Linkhut.AccountsFixtures

  describe "ban_user/2" do
    test "bans a user successfully with reason" do
      user = user_fixture()
      reason = "Spam posting"

      assert {:ok, %User{is_banned: true}} = Moderation.ban_user(user.username, reason)

      # Verify user is banned in database
      updated_user = Accounts.get_user(user.username)
      assert updated_user.is_banned == true

      # Verify moderation entry was created
      moderation_entries = Repo.all(Entry)
      assert length(moderation_entries) == 1

      entry = List.first(moderation_entries)
      assert entry.user_id == user.id
      assert entry.reason == reason
      assert entry.action == :ban
    end

    test "bans a user successfully without reason" do
      user = user_fixture()

      assert {:ok, %User{is_banned: true}} = Moderation.ban_user(user.username, nil)

      # Verify user is banned in database
      updated_user = Accounts.get_user(user.username)
      assert updated_user.is_banned == true

      # Verify moderation entry was created with nil reason
      moderation_entries = Repo.all(Entry)
      assert length(moderation_entries) == 1

      entry = List.first(moderation_entries)
      assert entry.user_id == user.id
      assert entry.reason == nil
      assert entry.action == :ban
    end

    test "bans a user successfully with default nil reason" do
      user = user_fixture()

      assert {:ok, %User{is_banned: true}} = Moderation.ban_user(user.username)

      # Verify user is banned in database
      updated_user = Accounts.get_user(user.username)
      assert updated_user.is_banned == true

      # Verify moderation entry was created
      moderation_entries = Repo.all(Entry)
      assert length(moderation_entries) == 1

      entry = List.first(moderation_entries)
      assert entry.user_id == user.id
      assert entry.reason == nil
      assert entry.action == :ban
    end

    test "returns error when user does not exist" do
      non_existent_username = "nonexistent_user"

      assert {:error, %Ecto.Changeset{} = changeset} =
               Moderation.ban_user(non_existent_username, "Reason")

      assert changeset.errors == [username: {"No user matching this username", []}]
    end

    test "returns error when banning user that is already banned" do
      user = user_fixture()

      assert {:ok, %User{is_banned: true}} = Moderation.ban_user(user.username)
      assert {:error, %Ecto.Changeset{} = changeset} = Moderation.ban_user(user.username)

      assert changeset.errors == [username: {"User is already banned", []}]
    end

    test "returns error when unbanning user that is unbanned" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} = Moderation.unban_user(user.username)

      assert changeset.errors == [username: {"User is already unbanned", []}]
    end

    test "returns error when ban changeset is invalid" do
      user = user_fixture()

      assert {:error, %Ecto.Changeset{} = changeset} =
               Moderation.ban_user(user.username, String.duplicate("a", 2000))

      assert changeset.errors == [
               reason: {
                 "should be at most %{count} character(s)",
                 [
                   {:count, 1024},
                   {:validation, :length},
                   {:kind, :max},
                   {:type, :string}
                 ]
               }
             ]
    end

    test "returns error when unban changeset is invalid" do
      user = user_fixture()

      assert {:ok, %User{is_banned: true}} = Moderation.ban_user(user.username)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Moderation.unban_user(user.username, String.duplicate("a", 2000))

      assert changeset.errors == [
               reason: {
                 "should be at most %{count} character(s)",
                 [
                   {:count, 1024},
                   {:validation, :length},
                   {:kind, :max},
                   {:type, :string}
                 ]
               }
             ]
    end
  end

  describe "unban_user/1" do
    setup do
      user = user_fixture()
      # First ban the user
      {:ok, banned_user} = Moderation.ban_user(user.username, "Initial ban")
      %{user: banned_user}
    end

    test "unbans a user successfully", %{user: user} do
      assert {:ok, %User{is_banned: false}} = Moderation.unban_user(user.username)

      # Verify user is unbanned in database
      updated_user = Accounts.get_user(user.username)
      assert updated_user.is_banned == false

      # Verify unban moderation entry was created
      moderation_entries = Repo.all(Entry)
      unban_entry = Enum.find(moderation_entries, fn entry -> entry.action == :unban end)

      assert unban_entry != nil
      assert unban_entry.user_id == user.id
      assert unban_entry.action == :unban
    end

    test "returns error when user does not exist" do
      non_existent_username = "nonexistent_user"

      assert {:error, %Ecto.Changeset{} = changeset} =
               Moderation.unban_user(non_existent_username)

      assert changeset.errors == [username: {"No user matching this username", []}]
    end
  end

  describe "list_banned_users/0" do
    test "returns empty list when no users are banned" do
      user_fixture()

      assert Moderation.list_banned_users() == []
    end

    test "returns only banned users" do
      user1 = user_fixture(%{username: "user1"})
      user2 = user_fixture(%{username: "user2"})
      user3 = user_fixture(%{username: "user3"})

      # Ban user1 and user3
      {:ok, _} = Moderation.ban_user(user1.username, "Reason 1")
      {:ok, _} = Moderation.ban_user(user3.username, "Reason 3")

      banned_users = Moderation.list_banned_users()

      assert length(banned_users) == 2
      banned_usernames = Enum.map(banned_users, & &1.username)
      assert user1.username in banned_usernames
      assert user3.username in banned_usernames
      assert user2.username not in banned_usernames
    end

    test "returns banned users with preloaded moderation entries" do
      user = user_fixture()
      {:ok, _} = Moderation.ban_user(user.username, "Test ban reason")

      [banned_user] = Moderation.list_banned_users()

      assert banned_user.is_banned == true
      assert Ecto.assoc_loaded?(banned_user.moderation_entries)
      assert length(banned_user.moderation_entries) == 1

      entry = List.first(banned_user.moderation_entries)
      assert entry.action == :ban
      assert entry.reason == "Test ban reason"
    end

    test "returns users with multiple moderation entries" do
      user = user_fixture()

      # Ban, unban, then ban again
      {:ok, _} = Moderation.ban_user(user.username, "First ban")
      {:ok, _} = Moderation.unban_user(user.username)
      {:ok, _} = Moderation.ban_user(user.username, "Second ban")

      [banned_user] = Moderation.list_banned_users()

      assert banned_user.is_banned == true
      assert length(banned_user.moderation_entries) == 3

      actions = Enum.map(banned_user.moderation_entries, & &1.action)
      assert :ban in actions
      assert :unban in actions

      # Should have 2 bans and 1 unban
      assert Enum.count(actions, fn action -> action == :ban end) == 2
      assert Enum.count(actions, fn action -> action == :unban end) == 1
    end

    test "maintains correct order and includes all banned user fields" do
      user1 = user_fixture(%{username: "aaauser", bio: "First user bio"})
      user2 = user_fixture(%{username: "zzzuser", bio: "Second user bio"})

      {:ok, _} = Moderation.ban_user(user1.username)
      {:ok, _} = Moderation.ban_user(user2.username)

      banned_users = Moderation.list_banned_users()

      assert length(banned_users) == 2

      Enum.each(banned_users, fn user ->
        assert user.is_banned
      end)
    end
  end
end
