defmodule Linkhut.Dump.HTMLParser do
  @moduledoc """
  A parser for the Netscape Bookmark File Format.
  """
  @root_node "linkhut"
  @error_node "__ERROR_TAG__"

  def parse_document(html) do
    html = "<#{@root_node}>#{html}</#{@root_node}>"
    {@root_node, [], parsed} = :mochiweb_html.parse(html)

    bookmarks =
      parse_tree(parsed, [])
      |> Enum.chunk_while(
        [],
        fn
          {"dt", _, _} = elem, acc ->
            if length(acc) == 0 do
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
        {"dt", [], [{"a", _, _}]} -> {rest, [item | acc]}
        {"dd", [], [<<_::binary>>]} -> {rest, [item | acc]}
        {_, _, items} -> {rest ++ items, acc}
        _ -> {rest, acc}
      end

    parse_tree(rest, acc)
  end

  defp parse_tree(_, acc) do
    Enum.reverse(acc)
  end

  defp parse_bookmark([{"dt", [], [{"a", params, [<<title::binary>>]}]}]) do
    to_link(title, "", params)
  end

  defp parse_bookmark([{"dt", [], [{"a", params, [<<title::binary>>]}]}, {"dd", [], []}]) do
    to_link(title, "", params)
  end

  defp parse_bookmark([
         {"dt", [], [{"a", params, [<<title::binary>>]}]},
         {"dd", [], [<<notes::binary>>]}
       ]) do
    to_link(title, notes, params)
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
       title: title,
       notes: notes,
       tags: Map.get(params, "tags", []),
       is_private: is_private(params),
       inserted_at:
         DateTime.from_unix!(
           Map.get(params, "add_date", Integer.to_string(:os.system_time(:second)))
           |> String.to_integer()
         )
     }}
  end

  defp to_link(title, _, _) do
    {:error, "No URL found for entry with title: '#{title}'"}
  end

  defp to_html(tokens) do
    {@error_node, [], tokens}
    |> :mochiweb_html.to_html()
    |> Enum.join()
    |> String.replace(~r/^<#{@error_node}>/, "")
    |> String.replace(~r/<\/#{@error_node}>$/, "")
  end

  defp is_private(%{"private" => value}) when value in ~w{1 true yes}, do: true
  defp is_private(%{} = _), do: false
end
