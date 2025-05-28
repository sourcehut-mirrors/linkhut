defmodule LinkhutWeb.Api.PostsXML do
  use LinkhutWeb, :xml

  import XmlBuilder

  def error(_), do: build_doc(:result, %{code: "something went wrong"})

  def done(_), do: build_doc(:result, %{code: "done"})

  def update(%{last_update: last_update}) do
    build_doc(:update, %{
      code: "done",
      inboxnew: "",
      time: DateTime.to_iso8601(last_update)
    })
  end

  def get(%{conn: conn, links: links, tag: tag, meta: show_meta} = params) do
    dt = Map.get(params, :date, "") |> encode_date()

    build_doc(
      :posts,
      %{dt: dt, tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, meta: show_meta) end)
    )
  end

  def recent(%{conn: conn, date: date, tag: tag, links: links}) do
    build_doc(
      :posts,
      %{dt: Date.to_iso8601(date), tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l) end)
    )
  end

  def dates(%{conn: conn, tag: tag, dates: dates}) do
    build_doc(
      :dates,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(dates, fn {date, cnt} -> element(:date, %{date: date, count: cnt}) end)
    )
  end

  def all(%{conn: conn, tag: tag, links: links, meta: show_meta}) do
    build_doc(
      :posts,
      %{tag: tag, user: conn.assigns[:current_user].username},
      Enum.map(links, fn l -> post(l, meta: show_meta) end)
    )
  end

  def all_hashes(%{links: links}) do
    build_doc(
      :posts,
      Enum.map(links, fn l ->
        element(:post, %{url: md5(l.url), meta: md5(DateTime.to_iso8601(l.updated_at))})
      end)
    )
  end

  def suggest(%{popular: popular, recommended: recommended}) do
    build_doc(:suggest, [
      Enum.map(popular, fn t -> element(:popular, t) end),
      Enum.map(recommended, fn t -> element(:recommended, t) end)
    ])
  end

  # Helpers

  defp build_doc(name, attrs), do: document(name, attrs) |> generate()

  defp build_doc(name, attrs, children), do: document(name, attrs, children) |> generate()

  defp encode_date(""), do: ""
  defp encode_date(%Date{} = date), do: Date.to_iso8601(date)

  defp post(link, opts \\ []) do
    show_meta = Keyword.get(opts, :meta)

    base_attrs = %{
      href: link.url,
      description: link.title,
      extended: link.notes,
      hash: md5(link.url),
      others: max(link.saves - 1, 0),
      tag: Enum.join(link.tags, " "),
      time: DateTime.to_iso8601(link.inserted_at)
    }

    attrs =
      if show_meta,
        do: Map.put(base_attrs, :meta, md5(DateTime.to_iso8601(link.updated_at))),
        else: base_attrs

    element(:post, attrs)
  end

  defp md5(value) do
    :crypto.hash(:md5, value) |> Base.encode16(case: :lower)
  end
end
