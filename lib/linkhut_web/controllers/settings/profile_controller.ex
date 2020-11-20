defmodule LinkhutWeb.Settings.ProfileController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.SettingsView

  alias Linkhut.Accounts

  def show(conn, _) do
    user = conn.assigns[:current_user]
    changeset = Accounts.change_user(user)

    render(conn, "profile.html", changeset: changeset)
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns[:current_user]

    if user != nil do
      case Accounts.update_user(user, user_params) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Profile updated")
          |> redirect(to: Routes.profile_path(conn, :show))

        {:error, changeset} ->
          conn
          |> render("profile.html", user: user, changeset: changeset)
      end
    else
      conn
      |> put_flash(:error, "No access")
      |> redirect(to: Routes.recent_path(conn, :show))
    end
  end
end
