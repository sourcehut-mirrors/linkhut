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
    with {:ok, _} <- Moderation.ban_user(username, Map.get(params, "ban_reason")) do
      render(conn, :admin,
        form: Phoenix.Component.to_form(%{}, as: "ban"),
        banned_users: Moderation.list_banned_users()
      )
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(changeset, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )

      _ ->
        render(conn, :admin,
          form:
            Phoenix.Component.to_form(params,
              as: "ban",
              errors: [username: {"No user matching this username was found", []}]
            ),
          banned_users: Moderation.list_banned_users()
        )
    end
  end

  def unban(conn, %{"username" => username} = params) do
    with {:ok, _} <- Moderation.unban_user(username) do
      render(conn, :admin,
        form: Phoenix.Component.to_form(%{}, as: "ban"),
        banned_users: Moderation.list_banned_users()
      )
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :admin,
          form: Phoenix.Component.to_form(changeset, as: "ban"),
          banned_users: Moderation.list_banned_users()
        )
    end
  end
end
