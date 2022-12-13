defmodule LinkhutWeb.LinkView do
  use LinkhutWeb, :view

  alias Atomex.{Entry, Feed}
  alias Linkhut.Accounts
  alias Linkhut.Search.Context
  alias LinkhutWeb.Router.Helpers, as: RouteHelpers

  @doc """
  Provides the path of the current context with the provided parameters

  ## Options

  Accepts one of the following options:
    * `:username` - reduce the context to the given username (resets page)
    * `:tag` - reduce the context to the given tag (resets page)
    * `:page` - provides results for the given page

  ## Examples

  Given a current path of `"/foo"`

      iex> current_path(conn, username: "bob")
      "/~bob/foo"
      iex> current_path(conn, page: 3)
      "/foo?p=3"
      iex> current_path(conn, tag: "bar")
      "/foo/bar"
  """
  @spec current_path(Plug.Conn.t(), Keyword.t()) :: String.t()
  def current_path(conn, opts)

  def current_path(%Plug.Conn{query_params: params} = conn, username: username) do
    current_path(conn, %Context{Map.drop(context(conn), [:url]) | from: Accounts.get_user(username)}, Map.drop(params, ["p"]))
  end

  def current_path(%Plug.Conn{query_params: params} = conn, url: url) do
    current_path(conn, %Context{context(conn) | url: url}, Map.drop(params, ["p"]))
  end

  def current_path(%Plug.Conn{query_params: params} = conn, tag: tag) do
    current_path(
      conn,
      Map.update(context(conn), :tagged_with, [], fn v ->
        Enum.uniq_by(v ++ [tag], &String.downcase/1)
      end),
      Map.drop(params, ["p"])
    )
  end

  def current_path(%Plug.Conn{query_params: params} = conn, page: page) do
    current_path(conn, context(conn), Map.put(params, :p, page))
  end

  def current_path(conn, %Context{} = context, params) do
    case context do
      %{from: user, url: url, tagged_with: tags}
      when not is_nil(user) and is_binary(url) and tags != [] ->
        RouteHelpers.user_bookmark_tags_path(conn, :show, user.username, url, tags, params)

      %{from: user, url: url} when not is_nil(user) and is_binary(url) ->
        RouteHelpers.user_bookmark_path(conn, :show, user.username, url, params)

      %{url: url, tagged_with: tags} when is_binary(url) and tags != [] ->
        RouteHelpers.bookmark_tags_path(conn, :show, url, tags, params)

      %{url: url} when is_binary(url) ->
        RouteHelpers.bookmark_path(conn, :show, url, params)

      %{from: user, tagged_with: tags} when not is_nil(user) and tags != [] ->
        RouteHelpers.user_tags_path(conn, :show, user.username, tags, params)

      %{from: user} when not is_nil(user) ->
        RouteHelpers.user_path(conn, :show, user.username, params)

      %{tagged_with: tags} when tags != [] ->
        RouteHelpers.tags_path(conn, :show, tags, params)

      _ ->
        RouteHelpers.link_path(conn, :show, params)
    end
  end

  @doc """
  Provides the path to the feed view of the current page
  """
  def feed_path(%Plug.Conn{} = conn) do
    case context(conn) do
      %{from: user, url: url, tagged_with: tags}
      when not is_nil(user) and is_binary(url) and tags != [] ->
        RouteHelpers.feed_user_bookmark_tags_path(conn, :show, user.username, url, tags)

      %{from: user, url: url} when not is_nil(user) and is_binary(url) ->
        RouteHelpers.feed_user_bookmark_path(conn, :show, user.username, url)

      %{url: url, tagged_with: tags} when is_binary(url) and tags != [] ->
        RouteHelpers.feed_bookmark_tags_path(conn, :show, url, tags)

      %{url: url} when is_binary(url) ->
        RouteHelpers.feed_bookmark_path(conn, :show, url)

      %{from: user, tagged_with: tags} when not is_nil(user) and tags != [] ->
        RouteHelpers.feed_user_tags_path(conn, :show, user.username, tags)

      %{from: user} when not is_nil(user) ->
        RouteHelpers.feed_user_path(conn, :show, user.username)

      %{tagged_with: tags} when tags != [] ->
        RouteHelpers.feed_tags_path(conn, :show, tags)

      _ ->
        RouteHelpers.feed_link_path(conn, :show)
    end
  end

  defp context(%Plug.Conn{} = conn) do
    conn.assigns.context
  end

  @doc """
  Renders a feed of links
  """
  def render("index.xml", %{
        conn: conn,
        context: %Context{} = context,
        links: links
      }) do
    title = title(context)
    uri = %URI{scheme: conn.scheme |> to_string, host: conn.host, port: conn.port}
    feed_url = URI.merge(uri, feed_path(conn))
    html_url = URI.merge(uri, current_path(conn, context, %{}))

    render_feed(title, feed_url, html_url, links)
  end

  defp title(%Context{} = context) do
    case context do
      %{from: user, url: url, tagged_with: tags} when not is_nil(user) and is_binary(url) and tags != [] ->
        LinkhutWeb.Gettext.gettext("Bookmarks for url: %{url} by linkhut user: %{user} tagged with: %{tags}", url: url, tags: Enum.join(tags, ","), user: user.username)

      %{from: user, url: url} when not is_nil(user) and is_binary(url) ->
        LinkhutWeb.Gettext.gettext("Bookmarks for url: %{url} by linkhut user: %{user}", url: url, user: user.username)

      %{url: url, tagged_with: tags} when is_binary(url) and tags != [] ->
        LinkhutWeb.Gettext.gettext("Bookmarks for url: %{url} tagged with: %{tags}", url: url, tags: Enum.join(tags, ","))

      %{url: url} when is_binary(url) ->
        LinkhutWeb.Gettext.gettext("Bookmarks for url: %{url}", url: url)

      %{from: user, tagged_with: tags} when not is_nil(user) and tags != [] ->
        LinkhutWeb.Gettext.gettext("Bookmarks by linkhut user: %{user} tagged with: %{tags}", tags: Enum.join(tags, ","), user: user.username)

      %{from: user} when not is_nil(user) ->
        LinkhutWeb.Gettext.gettext("Bookmarks by linkhut user: %{user}", user: user.username)

      %{tagged_with: tags} when tags != [] ->
        LinkhutWeb.Gettext.gettext("Bookmarks tagged with: %{tags}", tags: Enum.join(tags, ","))

      _ ->
        LinkhutWeb.Gettext.gettext("Recent bookmarks")
    end
  end

  defp render_feed(title, feed_url, html_url, links) do
    Feed.new(
      feed_url,
      DateTime.utc_now(),
      title
    )
    |> Feed.link(feed_url, rel: "self", type: "application/atom+xml")
    |> Feed.link(html_url, rel: "alternate", type: "text/html")
    |> Feed.entries(
      links.entries
      |> Enum.flat_map(fn links -> links end)
      |> Enum.map(fn link -> feed_entry(link, html_url) end)
    )
    |> Feed.build()
    |> Atomex.generate_document()
  end

  defp feed_entry(link, html_url) do
    Entry.new(link.url, link.inserted_at, link.title)
    |> Entry.link(link.url, rel: "alternate")
    |> Entry.content(link.notes)
    |> Entry.author(link.user.username, uri: html_url)
    |> (fn entry ->
          Enum.reduce(link.tags, entry, fn tag, entry ->
            Entry.category(entry, tag, label: tag)
          end)
        end).()
    |> Entry.build()
  end
end
