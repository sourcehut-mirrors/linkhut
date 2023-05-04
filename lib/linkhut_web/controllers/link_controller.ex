defmodule LinkhutWeb.LinkController do
  use LinkhutWeb, :controller

  alias Linkhut.Accounts
  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Pagination
  alias Linkhut.Search
  alias Linkhut.Search.Context
  alias Linkhut.Tags
  alias LinkhutWeb.Controllers.Utils

  @links_per_page 20
  @related_tags_limit 400

  def links_per_page, do: @links_per_page

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
        |> redirect(to: Routes.user_path(conn, :show, user.username))

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
      |> redirect(to: Routes.link_path(conn, :show))
    end
  end

  def update(conn, %{"link" => %{"url" => url} = link_params}) do
    user = conn.assigns[:current_user]
    link = Links.get(url, user.id)

    case Links.update_link(link, link_params) do
      {:ok, link} ->
        conn
        |> put_flash(:info, "Saved link: #{link.url}")
        |> redirect(to: Routes.user_path(conn, :show, user.username))

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
      |> redirect(to: Routes.link_path(conn, :show))
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
          |> redirect(to: Routes.user_path(conn, :show, user.username))

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

  defp has_query?(%{"query" => _}), do: true
  defp has_query?(_), do: false

  defp has_filters?(%{"username" => _}), do: true
  defp has_filters?(%{"tags" => _}), do: true
  defp has_filters?(%{"url" => _}), do: true
  defp has_filters?(_), do: false

  def show(conn, params) do
    cond do
      has_query?(params) -> query(conn, context(params), Map.get(params, "query"), page(params))
      has_filters?(params) -> filter(conn, context(params), page(params))
      true -> explore(conn, view(params), page(params))
    end
  end

  def unread(conn, params) do
    user = conn.assigns[:current_user]
    page = page(params)
    query = Map.get(params, "query", "")

    links_query =
      Search.search(
        %{context(params) | from: user, visible_as: user.username},
        query,
        Keyword.put(ordering(conn), :is_unread, true)
      )

    conn
    |> render("index.html",
      links: realize_query(links_query, page),
      tags: Tags.for_query(links_query, limit: @related_tags_limit),
      query: query,
      context: context(params),
      title: :unread
    )
  end

  defp ordering(%Plug.Conn{query_params: query_params} = _conn) do
    order =
      case query_params do
        %{"order" => "asc"} -> :asc
        %{"order" => "desc"} -> :desc
        _ -> nil
      end

    sort_by =
      case query_params do
        %{"sort" => "recency"} -> :recency
        %{"sort" => "popularity"} -> :popularity
        %{"sort" => "relevancy"} -> :relevancy
        %{"query" => query} when is_binary(query) and query != "" -> :relevancy
        _ -> nil
      end

    case {sort_by, order} do
      {nil, nil} -> []
      {nil, order} -> [order: order]
      {sort_by, nil} -> [sort_by: sort_by]
      {sort_by, order} -> [sort_by: sort_by, order: order]
    end
  end

  defp explore(conn, view, page) do
    context =
      case conn.assigns[:current_user] do
        nil -> %Context{}
        current_user -> %Context{visible_as: current_user.username}
      end

    links_query =
      case view do
        :recent -> Links.recent(ordering(conn))
        :popular -> Links.popular(ordering(conn))
      end

    conn
    |> render(:index,
      links: realize_query(links_query, page),
      tags: Tags.for_query(links_query, limit: @related_tags_limit),
      query: "",
      context: context,
      title: view,
      scope: Utils.scope(conn)
    )
  end

  defp query(conn, context, query, page) do
    context =
      case conn.assigns[:current_user] do
        nil -> context
        current_user -> %Context{context | visible_as: current_user.username}
      end

    links_query = Search.search(context, query, ordering(conn))

    conn
    |> render(:index,
      links: realize_query(links_query, page),
      tags: Tags.for_query(links_query, limit: @related_tags_limit),
      query: query,
      context: context,
      scope: Utils.scope(conn)
    )
  end

  defp filter(conn, %Context{} = context, page) do
    context =
      case conn.assigns[:current_user] do
        nil -> context
        current_user -> %Context{context | visible_as: current_user.username}
      end

    links_query = Search.search(context, "", ordering(conn))

    conn
    |> render(:index,
      links: realize_query(links_query, page),
      tags: Tags.for_query(links_query, limit: @related_tags_limit),
      query: "",
      context: context,
      scope: Utils.scope(conn)
    )
  end

  defp realize_query(query, page) do
    query
    |> Pagination.page(page, per_page: @links_per_page)
    |> Map.update!(
      :entries,
      &Enum.chunk_by(&1, fn link -> DateTime.to_date(link.inserted_at) end)
    )
  end

  defp context(%{"username" => username, "tags" => tags, "url" => url}) do
    %Context{
      from: Accounts.get_user!(username),
      tagged_with: Enum.uniq_by(tags, &String.downcase(&1)),
      url: URI.decode(url)
    }
  end

  defp context(%{"username" => username, "tags" => tags}) do
    %Context{
      from: Accounts.get_user!(username),
      tagged_with: Enum.uniq_by(tags, &String.downcase(&1))
    }
  end

  defp context(%{"username" => username, "url" => url}) do
    %Context{
      from: Accounts.get_user!(username),
      url: URI.decode(url)
    }
  end

  defp context(%{"tags" => tags, "url" => url}) do
    %Context{
      tagged_with: Enum.uniq_by(tags, &String.downcase/1),
      url: URI.decode(url)
    }
  end

  defp context(%{"tags" => tags}),
    do: %Context{tagged_with: Enum.uniq_by(tags, &String.downcase/1)}

  defp context(%{"username" => username}), do: %Context{from: Accounts.get_user!(username)}
  defp context(%{"url" => url}), do: %Context{url: URI.decode(url)}
  defp context(_), do: %Context{}

  defp page(%{"p" => page}), do: page
  defp page(_), do: 1

  defp view(%{"v" => "recent"}), do: :recent
  defp view(%{"v" => "popular"}), do: :popular
  defp view(_), do: :recent
end
