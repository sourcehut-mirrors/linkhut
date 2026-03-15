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
    with :error <- parse_epoch(value),
         :error <- parse_iso8601(value),
         :error <- parse_js_date(value) do
      DateTime.utc_now()
    else
      {:ok, datetime} -> datetime
    end
  end

  defp parse_epoch(value) do
    case Integer.parse(value) do
      {epoch, ""} -> DateTime.from_unix(epoch)
      _ -> :error
    end
  end

  defp parse_iso8601(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.shift_zone!(datetime, "Etc/UTC")}
      _ -> :error
    end
  end

  # Parses JS Date.toString() format, e.g.:
  # "Wed Mar 15 2023 17:06:40 GMT+0530 (India Standard Time)"
  @months %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  defp parse_js_date(value) do
    with {:ok, [_wday, month_str, day, year, hour, min, sec, _tz, sign, offset], _rest} <-
           :io_lib.fread(~c"~3s ~3s ~d ~d ~d:~d:~d ~3s~c~4d", String.to_charlist(value)),
         {:ok, month} <- Map.fetch(@months, List.to_string(month_str)),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, min, sec) do
      offset_secs = (div(offset, 100) * 3600 + rem(offset, 100) * 60) * sign_multiplier(sign)

      {:ok, naive |> NaiveDateTime.add(-offset_secs) |> DateTime.from_naive!("Etc/UTC")}
    else
      _ -> :error
    end
  end

  defp sign_multiplier(~c"-"), do: -1
  defp sign_multiplier(~c"+"), do: 1

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
