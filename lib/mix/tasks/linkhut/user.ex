defmodule Mix.Tasks.Linkhut.User do
  use Mix.Task

  import Mix.Linkhut
  alias Linkhut.Accounts
  alias Linkhut.Accounts.User
  alias Linkhut.Repo

  use Phoenix.VerifiedRoutes,
    endpoint: LinkhutWeb.Endpoint,
    router: LinkhutWeb.Router,
    statics: LinkhutWeb.static_paths()

  @moduledoc """
  Manages users in the Linkhut application.

  This task provides various user management operations including creating new users
  with optional admin privileges.

  ## Usage

      mix linkhut.user OPERATION [OPTIONS]

  """

  @shortdoc "Manages linkhut users"

  # Main command dispatcher
  def run(["new" | args]), do: create_user(args)
  def run(["reset_password", username]), do: reset_user_password(username)
  def run(["set" | args]), do: set_user_attributes(args)
  def run(["list"]), do: list_users()
  def run(_), do: shell_error("Invalid command. Use: new, reset_password, set, or list")

  defp create_user([username, email | rest]) do
    {options, [], []} =
      OptionParser.parse(
        rest,
        strict: [
          password: :string,
          admin: :boolean,
          assume_yes: :boolean
        ],
        aliases: [
          y: :assume_yes
        ]
      )

    {password, generated_password?} =
      case Keyword.get(options, :password) do
        nil ->
          {:crypto.strong_rand_bytes(16) |> Base.encode64(), true}

        password ->
          {password, false}
      end

    admin? = Keyword.get(options, :admin, false)
    assume_yes? = Keyword.get(options, :assume_yes, false)

    shell_info("""
    A user will be created with the following information:
      - username: #{username}
      - email: #{email}
      - password: #{if(generated_password?, do: "[generated; a reset link will be created]", else: password)}
      - admin: #{if(admin?, do: "true", else: "false")}
    """)

    proceed? = assume_yes? or shell_prompt("Continue?", "n") in ~w(Yn Y y)

    if proceed? do
      start_linkhut()

      params = %{
        username: username,
        credential: %{
          email: email,
          password: password,
          password_confirmation: password
        }
      }

      {:ok, user} = Accounts.create_user(params)
      {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      Accounts.confirm_user(user, encoded_token)

      shell_info("User #{username} created")

      if admin? do
        run(["set", username, "--admin"])
      end

      if generated_password? do
        run(["reset_password", username])
      end
    else
      shell_info("User will not be created.")
    end
  end

  defp reset_user_password(username) do
    start_linkhut()

    with %User{} = user <- Accounts.get_user(username),
         %User{credential: %{}} = user <- Repo.preload(user, :credential),
         {encoded_token, user_token} <-
           Accounts.UserToken.build_email_token(user, "reset_password") do
      Repo.insert!(user_token)
      shell_info("Generated password reset token for #{user.username}")

      url = url(~p"/_/reset-password/#{encoded_token}")

      shell_info("URL: #{url}")
    else
      _ ->
        shell_error("No user #{username}")
    end
  end

  defp set_user_attributes([username | rest]) do
    {options, [], []} =
      OptionParser.parse(
        rest,
        strict: [
          admin: :boolean
        ]
      )

    with %User{} = user <- Accounts.get_user(username) do
      _user =
        case Keyword.get(options, :admin) do
          nil -> user
          true -> set_admin_role(user)
        end
    else
      _ ->
        shell_error("No user #{username}")
    end
  end

  defp list_users() do
    start_linkhut()

    Linkhut.Repo.transaction(
      fn ->
        Linkhut.Accounts.User
        |> Linkhut.Repo.stream()
        |> Stream.map(fn user ->
          shell_info(
            "#{user.username} admin: #{Accounts.is_admin?(user)}, banned: #{user.is_banned}"
          )
        end)
        |> Stream.run()
      end,
      timeout: :infinity
    )
  end

  defp set_admin_role(user) do
    {:ok, user} = Accounts.set_admin_role(user)

    shell_info("Admin status of #{user.username}: #{Enum.member?(user.roles, :admin)}")
    user
  end
end
