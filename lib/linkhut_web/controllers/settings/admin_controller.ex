defmodule LinkhutWeb.Settings.AdminController do
  use LinkhutWeb, :controller

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Storage
  alias Linkhut.Moderation

  @moduledoc """
  Controller for admin operations
  """
  def show(conn, _) do
    render(conn, :admin,
      form: Phoenix.Component.to_form(%{}, as: "ban"),
      banned_users: Moderation.list_banned_users(),
      archiving_mode: Archiving.mode(),
      db_storage_used: Archiving.storage_used()
    )
  end

  def ban(conn, %{"ban" => %{"username" => username} = params}) do
    case Moderation.ban_user(username, Map.get(params, "reason")) do
      {:ok, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users(),
          archiving_mode: Archiving.mode(),
          db_storage_used: Archiving.storage_used()
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(params, errors: changeset.errors, as: "ban"),
          banned_users: Moderation.list_banned_users(),
          archiving_mode: Archiving.mode(),
          db_storage_used: Archiving.storage_used()
        )
    end
  end

  def unban(conn, %{"username" => username}) do
    case Moderation.unban_user(username) do
      {:ok, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users(),
          archiving_mode: Archiving.mode(),
          db_storage_used: Archiving.storage_used()
        )

      {:error, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users(),
          archiving_mode: Archiving.mode(),
          db_storage_used: Archiving.storage_used()
        )
    end
  end

  def recompute_storage(conn, _params) do
    Archiving.recompute_all_archive_sizes()

    {:ok, disk_bytes} = Storage.storage_used()
    db_bytes = Archiving.storage_used()

    conn
    |> put_flash(
      :info,
      "Storage recomputed. DB: #{Linkhut.Formatting.format_bytes(db_bytes)}, Disk: #{Linkhut.Formatting.format_bytes(disk_bytes)}"
    )
    |> redirect(to: ~p"/_/admin")
  end
end
