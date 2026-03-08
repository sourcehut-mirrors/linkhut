defmodule LinkhutWeb.Settings.AdminController do
  @moduledoc "Controller for admin operations."

  use LinkhutWeb, :controller

  alias Linkhut.Archiving
  alias Linkhut.Moderation

  def show(conn, _) do
    render_admin(conn, Phoenix.Component.to_form(%{}, as: "ban"))
  end

  def ban(conn, %{"ban" => %{"username" => username} = params}) do
    form =
      case Moderation.ban_user(username, Map.get(params, "reason")) do
        {:ok, _} ->
          Phoenix.Component.to_form(%{}, as: "ban")

        {:error, %Ecto.Changeset{} = changeset} ->
          Phoenix.Component.to_form(params, errors: changeset.errors, as: "ban")
      end

    render_admin(conn, form)
  end

  def unban(conn, %{"username" => username}) do
    Moderation.unban_user(username)
    render_admin(conn, Phoenix.Component.to_form(%{}, as: "ban"))
  end

  defp render_admin(conn, form) do
    render(conn, :admin,
      form: form,
      banned_users: Moderation.list_banned_users(),
      archive_stats: Archiving.admin_archive_stats()
    )
  end
end
