defmodule LinkhutWeb.LinkController do
  use LinkhutWeb, :controller

  alias Linkhut.Model.Link
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def new(conn, _) do
    conn
    |> render("add.html", changeset: Link.changeset())
  end

  def insert(conn, %{"link" => %{"url" => url} = link_params}) do
    user = Guardian.Plug.current_resource(conn)
    changeset = Link.changeset(%Link{user_id: user.id, url: url}, link_params)

    case Repo.insert(changeset) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Added link: #{link.url}")
        |> redirect(to: Routes.link_path(conn, :show, user.username))

      {:error, changeset} ->
        conn
        |> render("add.html", changeset: changeset)
    end
  end

  def edit(conn, %{"url" => url}) do
    user = Guardian.Plug.current_resource(conn)
    link = Repo.link(url, user.id)

    if link != nil do
      conn
      |> render("edit.html", changeset: Link.changeset(link))
    else
      conn
      |> put_flash(:error, "Couldn't find link for #{url}")
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end

  def update(conn, %{"link" => %{"url" => url} = link_params}) do
    user = Guardian.Plug.current_resource(conn)
    link = Repo.link(url, user.id)
    changeset = Link.changeset(link, link_params)

    case Repo.update(changeset) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Saved link: #{link.url}")
        |> redirect(to: Routes.link_path(conn, :show, user.username))

      {:error, changeset} ->
        conn
        |> render("edit.html", changeset: changeset)
    end
  end

  def remove(conn, %{"url" => url}) do
    user = Guardian.Plug.current_resource(conn)
    link = Repo.link(url, user.id)

    if link != nil do
      conn
      |> render("delete.html", link: link, changeset: Link.changeset(link))
    else
      conn
      |> put_flash(:error, "Couldn't find link for #{url}")
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end

  def delete(conn, %{"link" => %{"url" => url, "are_you_sure?" => confirmed} = link_params}) do
    user = Guardian.Plug.current_resource(conn)
    link = Repo.link(url, user.id)
    changeset = Link.changeset(link, link_params)

    if confirmed == "true" do
      case Repo.delete(changeset) do
        {:ok, link} ->
          conn
          |> put_flash(:info, "Deleted link: #{link.url}")
          |> redirect(to: Routes.link_path(conn, :show, user.username))

        {:error, changeset} ->
          conn
          |> render("delete.html", changeset: changeset)
      end
    else
      conn
      |> put_flash(:error, "Please confirm you want to delete this link")
      |> redirect(to: Routes.link_path(conn, :remove, url: url))
    end
  end

  def show(conn, %{"username" => username} = params) do
    page = Map.get(params, "p", 1)
    user = Repo.get_by(User, username: username)

    if user != nil do
      links = Repo.links_by_date([user_id: user.id], page: page)

      conn
      |> render("user.html", user: user, links: links, tags: Repo.tags(user_id: user.id))
    else
      conn
      |> put_flash(:error, "Wrong username")
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end
end
