defmodule LinkhutWeb.ApiView do
  @moduledoc false
  use LinkhutWeb, :view

  import XmlBuilder

  def render("update.xml", %{last_update: last_update}) do
    doc(:update, %{
      code: "done",
      inboxnew: "",
      time: DateTime.to_iso8601(last_update)
    })
  end

  def render("add.xml", %{link: _link}) do
    doc(:result, %{code: "done"})
  end

  def render("add.xml", %{changeset: _changeset}) do
    doc(:result, %{code: "something went wrong"})
  end

  def render("delete.xml", %{link: _link}) do
    doc(:result, %{code: "done"})
  end

  def render("delete.xml", %{changeset: _changeset}) do
    doc(:result, %{code: "something went wrong"})
  end

  def render("get.xml", %{conn: conn, links: links, tag: tag, meta: show_meta} = params) do
    dt =
      case Map.get(params, :date) do
        nil -> ""
        date -> Date.to_iso8601(date)
      end

    doc(
      :posts,
      %{dt: dt, tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, show_meta) end)
    )
  end

  def render("recent.xml", %{conn: conn, date: date, tag: tag, links: links}) do
    doc(
      :posts,
      %{dt: Date.to_iso8601(date), tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l) end)
    )
  end

  def render("dates.xml", %{conn: conn, tag: tag, links: links}) do
    dates =
      links
      |> Enum.frequencies_by(fn %{inserted_at: dt} -> DateTime.to_date(dt) end)
      |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})

    doc(
      :dates,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(dates, fn {date, cnt} -> element(:date, %{date: date, count: cnt}) end)
    )
  end

  def render("all.xml", %{conn: conn, tag: tag, links: links, meta: show_meta}) do
    doc(
      :posts,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, show_meta) end)
    )
  end

  def render("all?hashes.xml", %{links: links}) do
    doc(
      :posts,
      Enum.map(links, fn l ->
        element(:post, %{url: md5(l.url), meta: md5(DateTime.to_iso8601(l.updated_at))})
      end)
    )
  end

  def render("suggest.xml", %{popular: popular, recommended: recommended}) do
    doc(:suggest, [
      Enum.map(popular, fn t -> element(:popular, t) end),
      Enum.map(recommended, fn t -> element(:recommended, t) end)
    ])
  end

  defp post(link, show_meta \\ false) do
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

  defp md5(string) do
    :crypto.hash(:md5, string)
    |> Base.encode16(case: :lower)
  end
end
