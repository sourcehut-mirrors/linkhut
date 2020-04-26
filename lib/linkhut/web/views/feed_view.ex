defmodule Linkhut.Web.FeedView do
  use Linkhut.Web, :view

  alias Atomex.{Entry, Feed}

  def render("feed.xml", %{username: username, url: url, links: links}) do
    Feed.new(
      url,
      DateTime.utc_now(),
      Linkhut.Web.Gettext.gettext("Bookmarks for linkhut user: %{user}", user: username)
    )
    |> Feed.link(url, rel: "self", type: "application/atom+xml")
    |> Feed.entries(Enum.map(links, fn link -> feed_entry(link) end))
    |> Feed.build()
    |> Atomex.generate_document()
  end

  defp feed_entry(
         %{url: url, title: title, notes: notes, tags: tags, inserted_at: inserted_at, user: user} =
           _link
       ) do
    Entry.new(url, inserted_at, title)
    |> Entry.link(url, rel: "alternate")
    |> Entry.content(notes)
    |> Entry.author(user.username, uri: Linkhut.Web.Endpoint.url() <> "/~#{user.username}")
    |> (fn entry ->
          Enum.reduce(tags, entry, fn tag, entry -> Entry.category(entry, tag, label: tag) end)
        end).()
    |> Entry.build()
  end
end
