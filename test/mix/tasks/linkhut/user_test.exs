defmodule Mix.Tasks.Linkhut.UserTest do
  use Linkhut.DataCase, async: false

  import ExUnit.CaptureIO
  import Linkhut.Factory

  alias Linkhut.Accounts
  alias Linkhut.Accounts.{User, UserToken}
  alias Linkhut.Repo

  @moduletag :mix_task
  # Shared setup for shell mocking
  def setup_shell(_context) do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    setup :setup_shell

    test "handles 'reset_password' command" do
      user = insert(:user, username: "resetuser")
      insert(:credential, user: user, email: "reset@example.com")

      Mix.Tasks.Linkhut.User.run(["reset_password", "resetuser"])

      assert_token_created(user, "reset_password")
    end

    test "handles 'set' command" do
      insert(:user, username: "setuser")

      Mix.Tasks.Linkhut.User.run(["set", "setuser", "--admin"])

      updated_user = Accounts.get_user("setuser")
      assert Accounts.is_admin?(updated_user)
    end

    test "handles 'list' command" do
      insert(:user, username: "user1")
      insert(:user, username: "user2")

      Mix.Tasks.Linkhut.User.run(["list"])

      assert_shell_messages([
        {:info, "user1"},
        {:info, "user2"}])
    end

    test "shows error for invalid command" do
      Mix.Tasks.Linkhut.User.run(["invalid"])
      assert_received {:mix_shell, :error, [output]}
      assert output =~ "Invalid command"
    end
  end

  describe "new command" do
    setup :setup_shell

    test "creates user with confirmation" do
      send(self(), {:mix_shell_input, :prompt, "Y"})

      Mix.Tasks.Linkhut.User.run(["new", "testuser", "test@example.com"])

      assert_shell_messages([
        {:info, "user will be created"},
        {:prompt, "Continue"},
        {:info, "created"}
      ])

      user = Accounts.get_user("testuser")
      assert user.username == "testuser"
      refute Accounts.is_admin?(user)
    end

    test "cancels user creation" do
      send(self(), {:mix_shell_input, :prompt, "N"})

      Mix.Tasks.Linkhut.User.run(["new", "testuser", "test@example.com"])

      assert_shell_messages([
        {:info, "user will be created"},
        {:prompt, "Continue"},
        {:info, "will not be created"}
      ])

      refute Accounts.get_user("testuser")
    end

    test "creates admin user with --admin flag" do
      unsaved = build(:user)
      send(self(), {:mix_shell_input, :prompt, "Y"})

      Mix.Tasks.Linkhut.User.run(["new", unsaved.username, unsaved.credential.email, "--admin"])

      user = Accounts.get_user(unsaved.username)
      assert Accounts.is_admin?(user)
    end

    test "creates user with custom password" do
      Mix.Tasks.Linkhut.User.run([
        "new", "customuser", "custom@example.com",
        "--password", "custompass123", "--assume-yes"
      ])

      assert_shell_info_contains("password: custompass123")
      assert_shell_info_contains("User customuser created")

      assert {:ok, %User{}} =
               Accounts.authenticate_by_username_password("customuser", "custompass123")
    end

    test "generates password and reset token when none provided" do
      Mix.Tasks.Linkhut.User.run(["new", "genuser", "gen@example.com", "--assume-yes"])

      assert_shell_info_contains("password: [generated; a reset link will be created]")
      assert_shell_info_contains("User genuser created")
      assert_shell_info_contains("Generated password reset token")

      user = Accounts.get_user("genuser")
      assert_token_created(user, "reset_password")
    end

    test "creates confirmed user by default" do
      Mix.Tasks.Linkhut.User.run(["new", "confirmed", "confirmed@example.com", "--assume-yes"])

      user = Accounts.get_user("confirmed") |> Repo.preload(:credential)
      assert user.credential.email_confirmed_at
    end
  end

  describe "reset_password command" do
    setup :setup_shell

    test "generates reset token for existing user" do
      user = insert(:user, username: "resetuser")
      insert(:credential, user: user, email: "reset@example.com")

      Mix.Tasks.Linkhut.User.run(["reset_password", "resetuser"])

      assert_shell_info_contains("Generated password reset token for resetuser")
      assert_shell_info_contains("/_/reset-password/")
      assert_token_created(user, "reset_password")
    end

    test "shows error for non-existent user" do
      Mix.Tasks.Linkhut.User.run(["reset_password", "nonexistent"])
      assert_received {:mix_shell, :error, [output]}
      assert output =~ "No user nonexistent"
    end
  end

  describe "set command" do
    setup :setup_shell

    test "sets admin role" do
      insert(:user, username: "setuser")

      Mix.Tasks.Linkhut.User.run(["set", "setuser", "--admin"])

      assert_shell_info_contains("Admin status of setuser: true")
      assert Accounts.get_user("setuser") |> Accounts.is_admin?()
    end

    test "shows error for non-existent user" do
      Mix.Tasks.Linkhut.User.run(["set", "nonexistent", "--admin"])
      assert_received {:mix_shell, :error, [output]}
      assert output =~ "No user nonexistent"
    end

    test "handles no options gracefully" do
      insert(:user, username: "nooptsuser")

      Mix.Tasks.Linkhut.User.run(["set", "nooptsuser"])

      refute_received {:mix_shell, :info}
      refute Accounts.get_user("nooptsuser") |> Accounts.is_admin?()
    end
  end

  describe "list command" do
    test "lists users with attributes" do
      user1 = insert(:user, username: "listuser1", is_banned: false)
      insert(:user, username: "listuser2", is_banned: true)
      {:ok, _} = Accounts.set_admin_role(user1)

      output = capture_io(fn -> Mix.Tasks.Linkhut.User.run(["list"]) end)

      assert output =~ "listuser1 admin: true, banned: false"
      assert output =~ "listuser2 admin: false, banned: true"
    end

    test "handles empty user list" do
      Repo.delete_all(User)
      Mix.Tasks.Linkhut.User.run(["list"])
      refute_received {:mix_shell, :info}
    end
  end

  describe "error handling" do
    test "handles invalid email addresses" do
      assert_raise MatchError, fn ->
        capture_io(fn ->
          Mix.Tasks.Linkhut.User.run(["new", "invaliduser", "invalid-email", "--assume-yes"])
        end)
      end
    end

    test "handles duplicate usernames" do
      insert(:user, username: "duplicate")

      assert_raise MatchError, fn ->
        capture_io(fn ->
          Mix.Tasks.Linkhut.User.run(["new", "duplicate", "dup@example.com", "--assume-yes"])
        end)
      end
    end
  end

  # Helper functions
  defp assert_token_created(user, context) do
    assert Repo.exists?(
             from(t in UserToken,
               where: t.user_id == ^user.id and t.context == ^context)
           )
  end

  defp assert_shell_messages(expected_messages) do
    for {type, pattern} <- expected_messages do
      assert_received {:mix_shell, ^type, [message]}
      assert message =~ pattern
    end
  end

  defp assert_shell_info_contains(pattern) do
    assert_received {:mix_shell, :info, [message]}
    assert message =~ pattern
  end
end
