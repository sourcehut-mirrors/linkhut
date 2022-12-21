defmodule LinkhutWeb.Api.PostsView do
  @moduledoc false
  use LinkhutWeb, :view

  import XmlBuilder

  def render("update.xml", %{last_update: last_update}) do
    document(:update, %{
      code: "done",
      inboxnew: "",
      time: DateTime.to_iso8601(last_update)
    })
    |> generate()
  end

  def render("update.json", %{last_update: last_update}) do
    %{update_time: DateTime.to_iso8601(last_update)}
  end

  def render("add.xml", %{link: _link}) do
    document(:result, %{code: "done"})
    |> generate()
  end

  def render("add.json", %{link: _link}) do
    %{result_code: "done"}
  end

  def render("add.xml", %{changeset: _changeset}) do
    document(:result, %{code: "something went wrong"})
    |> generate()
  end

  def render("add.json", %{changeset: _changeset}) do
    %{result_code: "something went wrong"}
  end

  def render("delete.xml", %{link: _link}) do
    document(:result, %{code: "done"})
    |> generate()
  end

  def render("delete.json", %{link: _link}) do
    %{result_code: "done"}
  end

  def render("delete.xml", %{changeset: _changeset}) do
    document(:result, %{code: "something went wrong"})
    |> generate()
  end

  def render("delete.json", %{changeset: _changeset}) do
    %{result_code: "something went wrong"}
  end

  def render("get.xml", %{conn: conn, links: links, tag: tag, meta: show_meta} = params) do
    dt =
      case Map.get(params, :date) do
        nil -> ""
        date -> Date.to_iso8601(date)
      end

    document(
      :posts,
      %{dt: dt, tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, :xml, meta: show_meta) end)
    )
    |> generate()
  end

  def render("get.json", %{links: links, meta: show_meta}) do
    %{posts: Enum.map(links, fn l -> post(l, :json, meta: show_meta) end)}
  end

  def render("recent.xml", %{conn: conn, date: date, tag: tag, links: links}) do
    document(
      :posts,
      %{dt: Date.to_iso8601(date), tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, :xml) end)
    )
    |> generate()
  end

  def render("recent.json", %{links: links}) do
    %{posts: Enum.map(links, fn l -> post(l, :json, meta: true) end)}
  end

  def render("dates.xml", %{conn: conn, tag: tag, dates: dates}) do
    document(
      :dates,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(dates, fn {date, cnt} -> element(:date, %{date: date, count: cnt}) end)
    )
    |> generate()
  end

  def render("dates.json", %{dates: dates}) do
    %{dates: Enum.reduce(dates, %{}, fn {date, cnt}, result -> Map.put(result, date, cnt) end)}
  end

  def render("all.xml", %{conn: conn, tag: tag, links: links, meta: show_meta}) do
    document(
      :posts,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, :xml, meta: show_meta) end)
    )
    |> generate()
  end

  def render("all.json", %{links: links, meta: meta}) do
    Enum.map(links, fn l -> post(l, :json, meta: meta) end)
  end

  def render("all_hashes.xml", %{links: links}) do
    document(
      :posts,
      Enum.map(links, fn l ->
        element(:post, %{url: md5(l.url), meta: md5(DateTime.to_iso8601(l.updated_at))})
      end)
    )
    |> generate()
  end

  def render("all_hashes.json", %{links: links}) do
    Enum.map(links, fn l -> %{url: md5(l.url), meta: md5(DateTime.to_iso8601(l.updated_at))} end)
  end

  def render("suggest.xml", %{popular: popular, recommended: recommended}) do
    document(:suggest, [
      Enum.map(popular, fn t -> element(:popular, t) end),
      Enum.map(recommended, fn t -> element(:recommended, t) end)
    ])
    |> generate()
  end

  def render("suggest.json", %{popular: popular, recommended: recommended}),
    do: [%{popular: popular}, %{recommended: recommended}]

  defp post(link, format, params \\ [])

  defp post(link, :xml, params) do
    show_meta = Keyword.get(params, :meta)

    attributes = %{
      href: link.url,
      description: link.title,
      extended: link.notes,
      hash: md5(link.url),
      others: link.shares,
      tag: Enum.join(link.tags, " "),
      time: DateTime.to_iso8601(link.inserted_at)
    }

    attributes =
      if show_meta,
        do: Map.put(attributes, :meta, md5(DateTime.to_iso8601(link.updated_at))),
        else: attributes

    element(:post, attributes)
  end

  defp post(link, :json, params) do
    show_meta = Keyword.get(params, :meta)

    %{
      href: link.url,
      description: link.title,
      extended: link.notes,
      hash: md5(link.url),
      tags: Enum.join(link.tags, " "),
      shared: if(link.is_private, do: "no", else: "yes"),
      time: DateTime.to_iso8601(link.inserted_at),
      meta: if(show_meta, do: md5(DateTime.to_iso8601(link.updated_at)), else: nil),
      toread: if(link.is_unread, do: "yes", else: "no")
    }
  end

  defp md5(string) do
    :crypto.hash(:md5, string)
    |> Base.encode16(case: :lower)
  end
end
