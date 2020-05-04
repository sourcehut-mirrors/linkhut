defmodule LinkhutWeb.Settings.ProfileController do
  use LinkhutWeb, :controller

  plug :put_view, LinkhutWeb.SettingsView

  alias Linkhut.Model.User
  alias Linkhut.Repo

  def show(conn, _) do
    user = Guardian.Plug.current_resource(conn)
    changeset = User.changeset(user, %{})

    render(conn, "profile.html", user: user, changeset: changeset)
  end

  def update(conn, %{"user" => user_params}) do
    user = Guardian.Plug.current_resource(conn)

    if user != nil do
      changeset = User.changeset(user, user_params)

      case Repo.update(changeset) do
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
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
