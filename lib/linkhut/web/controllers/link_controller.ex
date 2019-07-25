defmodule Linkhut.Web.LinkController do
  use Linkhut.Web, :controller

  alias Linkhut.Model.Link
  alias Linkhut.Repo

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def new(conn, _) do
    conn
    |> render("add.html")
  end

  def save(conn, %{"link" => link_params}) do
    user = Guardian.Plug.current_resource(conn)
    changeset = Link.changeset(%Link{user_id: user.id}, link_params)

    case Repo.insert(changeset) do
      {:ok, _} ->
        conn
        |> redirect(to: Routes.link_path(conn, :show, user.username))

      {:error, changeset} ->
        conn
        |> render("add.html", changeset: changeset)
    end
  end

  def show(conn, %{"username" => username}) do
    cond do
      String.match?(username, ~r/[A-Za-z]+/) ->
        conn
        |> render("show.html", username: String.downcase(username))

      true ->
        conn
        |> put_flash(:error, "Wrong username")
        |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
