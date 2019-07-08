defmodule Linkhut.Web.UserController do
  use Linkhut.Web, :controller
  alias Linkhut.Model.User
  alias Linkhut.Repo
  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def index(conn, _params) do
    users = Repo.all(User)
    render(conn, "index.html", users: users)
  end

  def new(conn, _params) do
    cond do
      GuardianPlug.current_resource(conn) ->
        conn
        |> redirect(to: Routes.user_path(conn, :show))

      true ->
        conn
        |> render("new.html", changeset: User.changeset(%User{}, %{}))
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
        |> render("new.html", changeset: changeset)
    end
  end

  def show(conn, _) do
    cond do
      user = Guardian.Plug.current_resource(conn) ->
        changeset = User.changeset(user, %{})

        conn
        |> render("show.html", user: user, changeset: changeset)

      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.link_path(conn, :index))
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
            |> redirect(to: Routes.user_path(conn, :show))

          {:error, changeset} ->
            conn
            |> render("show.html", user: user, changeset: changeset)
        end

      :error ->
        conn
        |> put_flash(:error, "No access")
        |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
