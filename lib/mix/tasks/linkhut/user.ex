defmodule Mix.Tasks.Linkhut.User do
  use Mix.Task

  import Ecto.Query
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

  ## Usage

      mix linkhut.user COMMAND [OPTIONS]

  ## Commands

      new <username> <email> [--password <pass>] [--admin] [-y]
      list
      set <username> [--admin / --no-admin]
      reset_password <username>
      ban <username> [--reason <reason>]
      unban <username> [--reason <reason>]

  """

  @shortdoc "Manages linkhut users"

  def run(["new" | args]), do: create_user(args)
  def run(["reset_password", username]), do: reset_user_password(username)
  def run(["set" | args]), do: set_user_attributes(args)
  def run(["list"]), do: list_users()
  def run(["ban" | args]), do: ban_user(args)
  def run(["unban" | args]), do: unban_user(args)

  def run(_),
    do: shell_error("Invalid command. Use: new, list, set, reset_password, ban, or unban")

  defp create_user([username, email | rest]) do
    case parse_options(rest,
           strict: [password: :string, admin: :boolean, assume_yes: :boolean],
           aliases: [y: :assume_yes]
         ) do
      {:ok, options} -> prepare_create_user(username, email, options)
      {:error, message} -> shell_error(message)
    end
  end

  defp create_user(_) do
    shell_error(
      "Usage: mix linkhut.user new <username> <email> [--password <pass>] [--admin] [-y]"
    )
  end

  defp prepare_create_user(username, email, options) do
    {password, generated_password?} =
      case Keyword.get(options, :password) do
        nil -> {:crypto.strong_rand_bytes(16) |> Base.encode64(), true}
        password -> {password, false}
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

    proceed? = assume_yes? or shell_prompt("Continue?", "n") in ~w(Y y yes Yes)

    if proceed? do
      do_create_user(username, email, password, admin?, generated_password?)
    else
      shell_info("User will not be created.")
    end
  end

  defp do_create_user(username, email, password, admin?, generated_password?) do
    start_linkhut()

    params = %{
      username: username,
      credential: %{
        email: email,
        password: password,
        password_confirmation: password
      }
    }

    case Accounts.create_user(params) do
      {:ok, user} ->
        {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "confirm")
        Repo.insert!(user_token)
        Accounts.confirm_user(user, encoded_token)

        shell_info("User #{username} created.")

        if admin?, do: run(["set", username, "--admin"])
        if generated_password?, do: run(["reset_password", username])

      {:error, changeset} ->
        shell_error("Failed to create user: #{format_errors(changeset)}")
    end
  end

  defp reset_user_password(username) do
    start_linkhut()

    with %User{} = user <- Accounts.get_user(username),
         %User{credential: %{}} = user <- Repo.preload(user, :credential),
         {encoded_token, user_token} <-
           Accounts.UserToken.build_email_token(user, "reset_password") do
      Repo.insert!(user_token)
      shell_info("Generated password reset token for #{user.username}.")

      url = url(~p"/_/reset-password/#{encoded_token}")

      shell_info("URL: #{url}")
    else
      _ ->
        shell_error("No user #{username}.")
    end
  end

  defp set_user_attributes([username | rest]) do
    case parse_options(rest, strict: [admin: :boolean]) do
      {:ok, options} -> do_set_user_attributes(username, options)
      {:error, message} -> shell_error(message)
    end
  end

  defp set_user_attributes([]) do
    shell_error("Usage: mix linkhut.user set <username> [--admin / --no-admin]")
  end

  defp do_set_user_attributes(username, options) do
    start_linkhut()

    case Accounts.get_user(username) do
      %User{} = user -> apply_user_attributes(user, options)
      nil -> shell_error("No user #{username}.")
    end
  end

  defp apply_user_attributes(user, options) do
    case Keyword.get(options, :admin) do
      nil ->
        shell_error("No attribute specified. Use: --admin or --no-admin")

      true ->
        case Accounts.set_admin_role(user) do
          {:ok, user} ->
            shell_info("#{user.username}: admin=#{:admin in user.roles}")
        end

      false ->
        case Accounts.remove_admin_role(user) do
          {:ok, user} ->
            shell_info("#{user.username}: admin=#{:admin in user.roles}")
        end
    end
  end

  defp list_users() do
    start_linkhut()

    Repo.transaction(
      fn ->
        User
        |> order_by(:username)
        |> Repo.stream()
        |> Stream.each(&print_user/1)
        |> Stream.run()
      end,
      timeout: :infinity
    )
  end

  defp print_user(user) do
    admin = if Accounts.is_admin?(user), do: Owl.Data.tag(" admin", :cyan), else: ""
    banned = if user.is_banned, do: Owl.Data.tag(" banned", :red), else: ""

    [user.username, admin, banned]
    |> Owl.Data.to_chardata()
    |> IO.puts()
  end

  defp ban_user([username | rest]) do
    case parse_options(rest, strict: [reason: :string]) do
      {:ok, options} -> do_ban_user(username, options)
      {:error, message} -> shell_error(message)
    end
  end

  defp ban_user([]) do
    shell_error("Usage: mix linkhut.user ban <username> [--reason <reason>]")
  end

  defp do_ban_user(username, options) do
    reason = Keyword.get(options, :reason)
    start_linkhut()

    case Linkhut.Moderation.ban_user(username, reason) do
      {:ok, _user} ->
        reason_suffix = if reason, do: " Reason: #{reason}", else: ""
        shell_info("User #{username} has been banned.#{reason_suffix}")

      {:error, changeset} ->
        shell_error("Failed to ban user: #{format_errors(changeset)}")
    end
  end

  defp unban_user([username | rest]) do
    case parse_options(rest, strict: [reason: :string]) do
      {:ok, options} -> do_unban_user(username, options)
      {:error, message} -> shell_error(message)
    end
  end

  defp unban_user([]) do
    shell_error("Usage: mix linkhut.user unban <username> [--reason <reason>]")
  end

  defp do_unban_user(username, options) do
    reason = Keyword.get(options, :reason)
    start_linkhut()

    case Linkhut.Moderation.unban_user(username, reason) do
      {:ok, _user} ->
        reason_suffix = if reason, do: " Reason: #{reason}", else: ""
        shell_info("User #{username} has been unbanned.#{reason_suffix}")

      {:error, changeset} ->
        shell_error("Failed to unban user: #{format_errors(changeset)}")
    end
  end

  defp parse_options(args, parser_opts) do
    case OptionParser.parse(args, parser_opts) do
      {options, [], []} ->
        {:ok, options}

      {_, _, invalid} when invalid != [] ->
        flags = Enum.map_join(invalid, ", ", fn {flag, _} -> flag end)
        {:error, "Unknown option(s): #{flags}"}

      {_, extra, _} ->
        {:error, "Unexpected argument(s): #{Enum.join(extra, ", ")}"}
    end
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> flatten_errors()
    |> Enum.join(", ")
  end

  defp flatten_errors(errors, prefix \\ nil) do
    Enum.flat_map(errors, fn {field, value} ->
      field_name = if prefix, do: "#{prefix}.#{field}", else: to_string(field)
      flatten_field(field_name, value)
    end)
  end

  defp flatten_field(field_name, messages) when is_list(messages) do
    Enum.flat_map(messages, fn
      msg when is_binary(msg) -> ["#{field_name}: #{msg}"]
      nested when is_map(nested) -> flatten_errors(nested, field_name)
    end)
  end

  defp flatten_field(field_name, nested) when is_map(nested) do
    flatten_errors(nested, field_name)
  end
end
