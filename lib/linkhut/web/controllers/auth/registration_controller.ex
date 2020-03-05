defmodule Linkhut.Web.Auth.RegistrationController do
  use Linkhut.Web, :controller

  plug :put_view, Linkhut.Web.AuthView

  alias Linkhut.Model.User
  alias Linkhut.Repo
  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def new(conn, _params) do
    if GuardianPlug.current_resource(conn) do
      conn
      |> redirect(to: Routes.profile_path(conn, :show))
    else
      conn
      |> render("register.html", changeset: User.changeset(%User{}, %{}))
    end
  end

  def create(conn, %{"user" => user_params}) do
    changeset = User.registration_changeset(%User{}, user_params)

    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Linkhut.Web.Auth.login(user)
        |> put_flash(:info, "Welcome to linkhut!")
        |> redirect(to: Routes.link_path(conn, :index))

      {:error, changeset} ->
        conn
        |> render("register.html", changeset: changeset)
    end
  end
end
