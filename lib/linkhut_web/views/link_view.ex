defmodule LinkhutWeb.LinkView do
  use LinkhutWeb, :view

  alias Atomex.{Entry, Feed}
  alias Linkhut.Search.Context
  alias LinkhutWeb.Router.Helpers, as: RouteHelpers

  @doc """
  Provides the path to a new search context that includes the given tag
  """
  def with_tag_link(%Plug.Conn{path_info: ["~" <> username | path_segments]} = conn, tag) do
    RouteHelpers.user_tags_path(
      conn,
      :show,
      username,
      MapSet.to_list(MapSet.put(MapSet.new(path_segments), tag))
    )
  end

  def with_tag_link(%Plug.Conn{path_info: path_segments} = conn, tag) do
    RouteHelpers.link_path(
      conn,
      :show,
      MapSet.to_list(MapSet.put(MapSet.new(path_segments), tag))
    )
  end

  @doc """
  Provides the path to the feed view of the current page
  """
  def feed_link(%Plug.Conn{path_info: path_segments} = conn) do
    RouteHelpers.feed_link_path(conn, :show, path_segments)
  end

  @doc """
  Renders a feed of links
  """
  def render("index.xml", %{
        conn: conn,
        context: %Context{from: user, tagged_with: []},
        links: links
      })
      when not is_nil(user) do
    title = LinkhutWeb.Gettext.gettext("Bookmarks for linkhut user: %{user}", user: user.username)
    feed_url = Routes.feed_user_url(conn, :show, user.username)
    html_url = Routes.user_url(conn, :show, user.username)

    render_feed(title, feed_url, html_url, links)
  end

  def render("index.xml", %{
        conn: conn,
        context: %Context{from: user, tagged_with: tags},
        links: links
      })
      when not is_nil(user) do
    title =
      LinkhutWeb.Gettext.gettext("Bookmarks for linkhut user: %{user} and tagged with: %{tags}",
        user: user.username,
        tags: Enum.join(tags, ",")
      )

    feed_url = Routes.feed_user_tags_url(conn, :show, user.username, tags)
    html_url = Routes.user_tags_url(conn, :show, user.username, tags)

    render_feed(title, feed_url, html_url, links)
  end

  def render("index.xml", %{conn: conn, context: %Context{tagged_with: []}, links: links}) do
    title = LinkhutWeb.Gettext.gettext("Recent bookmarks")
    feed_url = Routes.feed_recent_url(conn, :show)
    html_url = Routes.recent_url(conn, :show)

    render_feed(title, feed_url, html_url, links)
  end

  def render("index.xml", %{conn: conn, context: %Context{tagged_with: tags}, links: links})
      when not is_nil(tags) do
    title =
      LinkhutWeb.Gettext.gettext("Bookmarks tagged with: %{tags}", tags: Enum.join(tags, ","))

    feed_url = Routes.feed_link_url(conn, :show, tags)
    html_url = Routes.link_url(conn, :show, tags)

    render_feed(title, feed_url, html_url, links)
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
