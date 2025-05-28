defmodule LinkhutWeb.Api.PostsJSON do
  use LinkhutWeb, :json

  def error(_), do: %{result_code: "something went wrong"}
  def done(_), do: %{result_code: "done"}

  def update(%{last_update: last_update}) do
    %{update_time: DateTime.to_iso8601(last_update)}
  end

  def get(%{links: links, meta: show_meta}) do
    %{posts: Enum.map(links, &post(&1, meta: show_meta))}
  end

  def recent(%{links: links}) do
    %{posts: Enum.map(links, &post(&1, meta: true))}
  end

  def dates(%{dates: dates}) do
    %{dates: Map.new(dates)}
  end

  def all(%{links: links, meta: meta}) do
    Enum.map(links, &post(&1, meta: meta))
  end

  def all_hashes(%{links: links}) do
    Enum.map(links, fn %{url: url, updated_at: updated_at} ->
      %{url: md5(url), meta: md5(DateTime.to_iso8601(updated_at))}
    end)
  end

  def suggest(%{popular: popular, recommended: recommended}) do
    [%{popular: popular}, %{recommended: recommended}]
  end

  defp post(link, params) do
    show_meta = Keyword.get(params, :meta)

    %{
      href: link.url,
      description: link.title,
      extended: link.notes,
      hash: md5(link.url),
      others: max(0, link.saves - 1),
      tags: Enum.join(link.tags, " "),
      shared: (link.is_private && "no") || "yes",
      time: DateTime.to_iso8601(link.inserted_at),
      meta: (show_meta && md5(DateTime.to_iso8601(link.updated_at))) || nil,
      toread: (link.is_unread && "yes") || "no"
    }
  end

  defp md5(string) do
    :crypto.hash(:md5, string)
    |> Base.encode16(case: :lower)
  end
end
