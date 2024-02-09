defmodule LinkhutWeb.Controllers.Utils.Tags do

  @related_tags_limit 400

  def parse_options(params \\ %{}) do
    Keyword.new()
    |> maybe_all(params)
    |> sort_by(params)
    |> order(params)
  end

  def to_map(tag_options) do
    %{}
    |> maybe_all(tag_options)
    |> sort_by(tag_options)
    |> order(tag_options)
  end

  defp maybe_all(%{} = map, limit: false), do: Map.put(map, "ta", "1")
  defp maybe_all(%{} = map, _), do: map

  defp maybe_all(opts, %{"ta" => "1"}), do: opts
  defp maybe_all(opts, _), do: Keyword.put(opts, :limit, @related_tags_limit)

  defp sort_by(%{} = map, sort_by: :usage), do: Map.put(map, "ts", "c")
  defp sort_by(%{} = map, sort_by: :alpha), do: Map.put(map, "ts", "a")
  defp sort_by(%{} = map, _), do: map

  defp sort_by(opts, %{"ts" => "c"}), do: Keyword.put(opts, :sort_by, :usage)
  defp sort_by(opts, %{"ts" => "a"}), do: Keyword.put(opts, :sort_by, :alpha)
  defp sort_by(opts, _), do: opts

  defp order(%{} = map, order: :asc), do: Map.put(map, "to", "a")
  defp order(%{} = map, order: :desc), do: Map.put(map, "to", "d")
  defp order(%{} = map, _), do: map

  defp order(opts, %{"to" => "a"}), do: Keyword.put(opts, :order, :asc)
  defp order(opts, %{"to" => "d"}), do: Keyword.put(opts, :order, :desc)
  defp order(opts, _), do: opts
end
