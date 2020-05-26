defmodule LinkhutWeb.LinkController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Search
  alias Linkhut.Search.Term

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def new(conn, params) do
    conn
    |> render("add.html",
      changeset: Links.change_link(%Link{}, Map.take(params, ["url", "title", "tags"]))
    )
  end

  def insert(conn, %{"link" => link_params}) do
    user = conn.assigns[:current_user]

    case Links.create_link(user, link_params) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Added link: #{link.url}")
        |> redirect(to: Routes.link_path(conn, :show, ["~" <> user.username]))

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

  def delete(conn, %{"link" => %{"url" => url, "are_you_sure?" => confirmed} = _params}) do
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

  def search(conn, %{"query" => query} = params) when is_binary(query) do
    conn
    |> assign(:query, query)
    |> show(Map.put(params, "segments", String.split(query, ~r{\s}, trim: true)))
  end

  def show(conn, %{"segments" => segments} = params) when is_list(segments) do
    page = Map.get(params, "p", 1)

    links_for(conn, Enum.map(segments, &to_term/1), page)
  end

  defp to_term("~" <> username), do: Term.user(username)
  defp to_term(":" <> tag), do: Term.tag(tag)
  defp to_term(word), do: Term.word(word)

  defp links_for(conn, [{:user, username} | _], page) do
    user = Accounts.get_user!(username)
    links = Links.get_page_by_date([user_id: user.id], page: page)

    conn
    |> render(:user, user: user, links: links, tags: Links.get_tags(user_id: user.id))
  end

  defmodule RouteNotFound do
    defexception [:message, plug_status: 404]
  end

  defp links_for(_, terms, _) do
    raise RouteNotFound, "#{inspect(terms)}"
  end
end
