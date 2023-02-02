defmodule LinkhutWeb.Api.IFTT.TriggersView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("links.json", %{links: links}) do
    %{data: render_many(links, LinkhutWeb.Api.IFTT.TriggersView, "link.json", as: :link)}
  end

  def render("link.json", %{link: link}) do
    %{
      time: DateTime.to_iso8601(link.inserted_at),
      url: link.url,
      tags: Enum.join(link.tags, ","),
      notes: link.notes,
      title: link.title,
      meta: %{
        id: link.url,
        timestamp: DateTime.to_unix(link.inserted_at)
      }
    }
  end
end
