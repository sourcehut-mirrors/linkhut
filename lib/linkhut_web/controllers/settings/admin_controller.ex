defmodule LinkhutWeb.Settings.AdminController do
  use LinkhutWeb, :controller

  alias Linkhut.Moderation

  @moduledoc """
  Controller for admin operations
  """
  def show(conn, _) do
    render(conn, :admin,
      form: Phoenix.Component.to_form(%{}, as: "ban"),
      banned_users: Moderation.list_banned_users()
    )
  end

  def ban(conn, %{"ban" => %{"username" => username} = params}) do
    case Moderation.ban_user(username, Map.get(params, "reason")) do
      {:ok, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(params, errors: changeset.errors, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )
    end
  end

  def unban(conn, %{"username" => username}) do
    case Moderation.unban_user(username) do
      {:ok, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )

      {:error, _} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(%{}, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )
    end
  end
end
