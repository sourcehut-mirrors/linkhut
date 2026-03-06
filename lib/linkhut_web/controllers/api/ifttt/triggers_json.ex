defmodule LinkhutWeb.Api.IFTTT.TriggersJSON do
  @moduledoc false

  def links(%{links: links}) do
    %{data: Enum.map(links, &link/1)}
  end

  defp link(link) do
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
