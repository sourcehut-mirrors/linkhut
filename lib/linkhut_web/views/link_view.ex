defmodule LinkhutWeb.LinkView do
  use LinkhutWeb, :view
  use Timex

  alias Atomex.{Entry, Feed}
  alias Timex.Duration

  @doc """
  Makes dates pretty
  """
  def prettify(date) do
    days_ago =
      Duration.diff(Duration.now(), Duration.from_days(Date.diff(date, ~D[1970-01-01])), :days)

    cond do
      days_ago < 1 ->
        "Today"

      days_ago <= 2 ->
        LinkhutWeb.Gettext.gettext("Yesterday")

      days_ago < 10 ->
        Timex.format!(date, "{relative}", :relative)

      true ->
        Timex.format!(date, "{0D} {Mshort} {0YY}")
    end
  end

  @doc """
  Renders a feed of links under a user context
  """
  def render("user.xml", %{conn: conn, user: user, links: links}) do
    feed_url = Routes.feed_link_url(conn, :show, user.username)
    html_url = Routes.link_url(conn, :show, user.username)

    Feed.new(
      feed_url,
      DateTime.utc_now(),
      LinkhutWeb.Gettext.gettext("Bookmarks for linkhut user: %{user}", user: user.username)
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

  defp feed_entry(
         %{
           url: url,
           title: title,
           notes: notes,
           tags: tags,
           inserted_at: inserted_at,
           user: user
         },
         html_url
       ) do
    Entry.new(url, inserted_at, title)
    |> Entry.link(url, rel: "alternate")
    |> Entry.content(notes)
    |> Entry.author(user.username, uri: html_url)
    |> (fn entry ->
          Enum.reduce(tags, entry, fn tag, entry -> Entry.category(entry, tag, label: tag) end)
        end).()
    |> Entry.build()
  end
end
