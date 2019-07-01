defmodule Linkhut.Web.UserController do
  use Linkhut.Web, :controller
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def index(conn, _params) do
    users = Repo.all(User)
    render(conn, "index.html", users: users)
  end

  def new(conn, _params) do
    changeset = User.changeset(%User{}, %{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    changeset = User.registration_changeset(%User{}, user_params)
    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Linkhut.Web.Auth.login(user)
        |> put_flash(:info, "Welcome to linkhut!")
        |> redirect(to: Routes.user_path(conn, :index))
      {:error, changeset} ->
        conn
        |> render("new.html", changeset: changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    user = Repo.get(User, id)
    changeset = User.changeset(user, %{})
    cond do
      user == Guardian.Plug.current_resource(conn) ->
        conn
        |> render("show.html", user: user, changeset: changeset)
      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end

  def update(conn, %{"id" => id, "user" => user_params}) do
    user = Repo.get(User, id)
    changeset = User.registration_changeset(user, user_params)
    cond do
      user == Guardian.Plug.current_resource(conn) ->
        case Repo.update(changeset) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "User updated")
            |> redirect(to: Routes.page_path(conn, :index))
          {:error, changeset} ->
            conn
            |> render("show.html", user: user, changeset: changeset)
        end
      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.page_path(conn, :index))
    end
  end
end
