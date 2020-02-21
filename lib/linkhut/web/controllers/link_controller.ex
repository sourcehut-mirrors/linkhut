defmodule Linkhut.Web.LinkController do
  use Linkhut.Web, :controller

  require Logger

  alias Linkhut.Model.Link
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def new(conn, _) do
    conn
    |> render("add.html", changeset: Link.changeset(%Link{}, %{}))
  end

  def save(conn, %{"link" => link_params}) do
    user = Guardian.Plug.current_resource(conn)
    changeset = Link.changeset(%Link{user_id: user.id}, link_params)

    case Repo.insert(changeset) do
      {:ok, _link} ->
        conn
        |> put_flash(:info, "Added link")
        |> redirect(to: Routes.link_path(conn, :show, user.username))

      {:error, changeset} ->
        conn
        |> render("add.html", changeset: changeset)
    end
  end

  def show(conn, %{"username" => username}) do
    user = Repo.get_by(User, username: username)
    links = Repo.links(user)

    cond do
      user ->
        conn
        |> render("user.html", user: user, links: links)

      true ->
        conn
        |> put_flash(:error, "Wrong username")
        |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
