defmodule Linkhut.AccountsTest do
  use Linkhut.DataCase

  alias Linkhut.Accounts

  import Linkhut.AccountsFixtures
  alias Linkhut.Accounts.{User, UserToken, Credential}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.credential.email)
    end
  end

  describe "authenticate_by_username_password/2" do
    test "does not return the user if the username does not exist" do
      assert {:error, :unauthorized} =
               Accounts.authenticate_by_username_password("unknown", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()

      assert {:error, :unauthorized} =
               Accounts.authenticate_by_username_password(user.username, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert {:ok, %User{id: ^id}} =
               Accounts.authenticate_by_username_password(user.username, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires username to be set" do
      {:error, changeset} = Accounts.create_user(%{})

      assert %{
               username: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} =
        Accounts.create_user(%{
          username: "foobar",
          credential: %{email: "not valid", password: "short"}
        })

      assert %{
               credential: %{
                 email: ["has invalid format"],
                 password: ["should be at least 6 character(s)"]
               }
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security" do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.create_user(%{
          username: "foobar",
          credential: %{email: too_long, password: too_long}
        })

      assert "should be at most 72 character(s)" in errors_on(changeset).credential.password
    end

    test "validates email uniqueness" do
      %{credential: %{email: email}} = user_fixture()

      {:error, changeset} =
        Accounts.create_user(%{username: "foobar1", credential: %{email: email}})

      assert "has already been taken" in errors_on(changeset).credential.email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} =
        Accounts.create_user(%{username: "foobar2", credential: %{email: String.upcase(email)}})

      assert "has already been taken" in errors_on(changeset).credential.email
    end

    test "registers users with a hashed password" do
      user_attributes = valid_user_attributes()
      {:ok, user} = Accounts.create_user(user_attributes)
      assert user.username == user_attributes.username
      assert is_binary(user.credential.password_hash)
      assert is_nil(user.credential.email_confirmed_at)
      assert is_nil(user.credential.password)
    end
  end

  describe "change_user/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user(%User{})
      assert changeset.required == [:username]
    end

    test "allows fields to be set" do
      username = unique_username()

      changeset =
        Accounts.change_user(
          %User{},
          valid_user_attributes(%{username: username})
        )

      assert changeset.valid?
      assert get_change(changeset, :username) == username
    end
  end

  describe "change_credential/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_credential(%Credential{})
      assert changeset.required == [:email]
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.credential.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "short",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 6 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.authenticate_by_username_password(user.username, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{credential: %Credential{password: "123456"}}) =~ "password: \"123456\""
    end
  end
end
