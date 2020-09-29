defmodule LinkhutWeb.LinkController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Pagination
  alias Linkhut.Search
  alias Linkhut.Search.Context

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def new(conn, params) do
    conn
    |> render("add.html",
      changeset: Links.change_link(%Link{}, Map.take(params, ["url", "title", "tags", "notes"]))
    )
  end

  def insert(conn, %{"link" => link_params}) do
    user = conn.assigns[:current_user]

    case Links.create_link(user, link_params) do
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
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    if link != nil do
      conn
      |> render("edit.html", changeset: Links.change_link(link))
    else
      conn
      |> put_flash(:error, "Couldn't find link for #{url}")
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end

  def update(conn, %{"link" => %{"url" => url} = link_params}) do
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    case Links.update_link(link, link_params) do
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
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    if link != nil do
      conn
      |> render("delete.html", link: link, changeset: Links.change_link(link))
    else
      conn
      |> put_flash(:error, "Couldn't find link for #{url}")
      |> redirect(to: Routes.link_path(conn, :index))
    end
  end

  def delete(conn, %{"link" => %{"url" => url, "are_you_sure?" => confirmed}}) do
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    if confirmed == "true" do
      case Links.delete_link(link) do
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

  def show(conn, %{"username" => username, "tags" => tags, "query" => query, "p" => page}) do
    context = %Context{from: username, tagged_with: tags}

    context =
      case conn.assigns[:current_user] do
        nil -> context
        current_user -> %{context | visible_as: current_user.username}
      end

    links =
      Search.search(context, query)
      |> Pagination.page(page, per_page: 20)
      |> Map.update!(
        :entries,
        &Enum.chunk_by(&1, fn link -> DateTime.to_date(link.inserted_at) end)
      )

    if username do
      user = Accounts.get_user!(username)

      conn
      |> render(:user,
        user: user,
        links: links,
        tags: Links.get_tags(user_id: user.id),
        query: query
      )
    else
      conn
      |> render("index.html", links: links)
    end
  end

  def show(conn, params) do
    show(conn, Map.merge(%{"username" => nil, "tags" => [], "query" => "", "p" => 1}, params))
  end
end
