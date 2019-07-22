defmodule Linkhut.Web.Settings.ProfileController do
  use Linkhut.Web, :controller

  plug :put_view, Linkhut.Web.SettingsView

  alias Linkhut.Model.User
  alias Linkhut.Repo

  def index(conn, _params) do
    users = Repo.all(User)
    render(conn, "index.html", users: users)
  end

  def show(conn, _) do
    cond do
      user = Guardian.Plug.current_resource(conn) ->
        changeset = User.changeset(user, %{})

        conn
        |> render("profile.html", user: user, changeset: changeset)

      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.link_path(conn, :index))
    end
  end

  def update(conn, %{"user" => user_params}) do
    user = Guardian.Plug.current_resource(conn)
    changeset = User.registration_changeset(user, user_params)

    cond do
      user == Guardian.Plug.current_resource(conn) ->
        case Repo.update(changeset) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Profile updated")
            |> redirect(to: Routes.profile_path(conn, :show))

          {:error, changeset} ->
            conn
            |> render("profile.html", user: user, changeset: changeset)
        end

      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
