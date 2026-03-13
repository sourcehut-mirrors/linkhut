defmodule Linkhut.DataTransfer.Parsers.Netscape do
  @moduledoc """
  A parser for the Netscape Bookmark File Format.
  """
  @behaviour Linkhut.DataTransfer.Parser

  @root_node "linkhut"
  @error_node "__ERROR_TAG__"

  @impl true
  def can_parse?(document) do
    String.contains?(document, "NETSCAPE-Bookmark-file-1") or
      Regex.match?(~r/<DT>\s*<A\s/i, document)
  end

  @impl true
  def parse_document(html) do
    html = "<#{@root_node}>#{html}</#{@root_node}>"
    {@root_node, [], parsed} = :mochiweb_html.parse(html)

    bookmarks =
      parse_tree(parsed, [])
      |> Enum.chunk_while(
        [],
        fn
          {"dt", _, _} = elem, acc ->
            if acc == [] do
              {:cont, [elem | acc]}
            else
              {:cont, Enum.reverse(acc), [elem]}
            end

          {"dd", _, _} = elem, acc ->
            {:cont, [elem | acc]}

          _, acc ->
            {:cont, acc}
        end,
        fn
          [] -> {:cont, []}
          acc -> {:cont, Enum.reverse(acc), []}
        end
      )
      |> Enum.map(&parse_bookmark/1)

    {:ok, bookmarks}
  end

  defp parse_tree([item | rest], acc) do
    {rest, acc} =
      case item do
        {"dt", _, [{"a", _, _}]} -> {rest, [item | acc]}
        {"dd", _, _} -> {rest, [item | acc]}
        {_, _, items} -> {rest ++ items, acc}
        _ -> {rest, acc}
      end

    parse_tree(rest, acc)
  end

  defp parse_tree(_, acc) do
    Enum.reverse(acc)
  end

  defp parse_bookmark([{"dt", _, [{"a", params, children}]}]) do
    to_link(extract_text(children), "", params)
  end

  defp parse_bookmark([{"dt", _, [{"a", params, children}]}, {"dd", _, dd_children}]) do
    to_link(extract_text(children), extract_text(dd_children) |> String.trim(), params)
  end

  defp parse_bookmark(unmatched) do
    {:error, "#{to_html(unmatched)}"}
  end

  defp to_link(title, notes, params) when is_list(params) do
    to_link(
      title,
      notes,
      params |> Enum.reduce(%{}, fn {key, value}, map -> Map.merge(map, %{key => value}) end)
    )
  end

  defp to_link(title, notes, %{"href" => url} = params) do
    {:ok,
     %{
       url: url,
       title: if(title == "", do: url, else: title),
       notes: notes,
       tags: Map.get(params, "tags", ""),
       is_private: private?(params),
       inserted_at:
         Map.get(params, "add_date")
         |> to_timestamp()
     }}
  end

  defp to_link(title, _, _) do
    {:error, "No URL found for entry with title: '#{title}'"}
  end

  defp extract_text(children) when is_list(children) do
    children
    |> Enum.map_join("", &extract_text/1)
  end

  defp extract_text(text) when is_binary(text), do: text
  defp extract_text({_tag, _attrs, children}), do: extract_text(children)
  defp extract_text(_), do: ""

  defp to_timestamp(nil), do: DateTime.utc_now()

  defp to_timestamp(value) do
    formats = [
      "{s-epoch}",
      "{ISO:Extended}",
      "{ISO:Extended:Z}",
      "{WDshort} {Mshort} {0D} {YYYY} {ISOtime} {Zabbr}{Z} (Coordinated Universal Time)"
    ]

    Enum.find_value(formats, Timex.now(), fn format ->
      case Timex.parse(value, format) do
        {:ok, datetime} -> datetime
        {:error, _} -> nil
      end
    end)
    |> Timex.to_datetime()
  end

  defp to_html(tokens) do
    {@error_node, [], tokens}
    |> :mochiweb_html.to_html()
    |> Enum.join()
    |> String.replace(~r/^<#{@error_node}>/, "")
    |> String.replace(~r/<\/#{@error_node}>$/, "")
  end

  defp private?(%{"private" => value}) when value in ~w{1 true yes}, do: true
  defp private?(%{} = _), do: false
end
