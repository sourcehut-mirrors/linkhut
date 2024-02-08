defmodule LinkhutWeb.LinkXML do
  use LinkhutWeb, :xml

  import LinkhutWeb.Controllers.Utils

  alias Atomex.{Entry, Feed}
  alias LinkhutWeb.Gettext

  @doc """
  Renders a feed of links
  """
  def render("index.xml", %{
        conn: conn,
        links: links,
        scope: scope
      }) do
    title = title(scope)
    uri = %URI{scheme: conn.scheme |> to_string, host: conn.host, port: conn.port}
    feed_url = URI.merge(uri, feed_path(conn))
    html_url = URI.merge(uri, html_path(conn))

    render_feed(title, feed_url, html_url, links)
  end

  defp title(%{} = scope) do
    scope
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> v != nil and v != [] end)
    |> Enum.into(%{})
    |> case do
      %{view: :unread} -> Gettext.gettext("Your Unread Bookmarks")
      %{user: user, url: url, tags: tags} ->
        Gettext.gettext(
          "Bookmarks for url: %{url} by linkhut user: %{user} tagged with: %{tags}",
          url: url,
          tags: Enum.join(tags, ","),
          user: user
        )

      %{user: user, url: url} ->
        Gettext.gettext("Bookmarks for url: %{url} by linkhut user: %{user}",
          url: url,
          user: user
        )

      %{url: url, tags: tags} ->
        Gettext.gettext("Bookmarks for url: %{url} tagged with: %{tags}",
          url: url,
          tags: Enum.join(tags, ",")
        )

      %{url: url} ->
        Gettext.gettext("Bookmarks for url: %{url}", url: url)

      %{user: user, tags: tags} ->
        Gettext.gettext("Bookmarks by linkhut user: %{user} tagged with: %{tags}",
          tags: Enum.join(tags, ","),
          user: user
        )

      %{user: user} ->
        Gettext.gettext("Bookmarks by linkhut user: %{user}", user: user)

      %{tags: tags} ->
        Gettext.gettext("Bookmarks tagged with: %{tags}", tags: Enum.join(tags, ","))

      %{params: %{"v" => "popular"}} ->
        Gettext.gettext("Popular bookmarks")

      _ ->
        Gettext.gettext("Recent bookmarks")
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
      |> Enum.map(fn link -> feed_entry(link) end)
    )
    |> Feed.build()
    |> Atomex.generate_document()
  end

  defp feed_entry(link) do
    Entry.new(link.url, link.inserted_at, link.title)
    |> Entry.link(link.url, rel: "alternate")
    |> Entry.content(link.notes)
    |> Entry.author(link.user.username, uri: url(~p"/~#{link.user.username}"))
    |> (fn entry ->
          Enum.reduce(link.tags, entry, fn tag, entry ->
            Entry.category(entry, tag, label: tag)
          end)
        end).()
    |> Entry.build()
  end
end
