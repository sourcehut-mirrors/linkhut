defmodule LinkhutWeb.Api.TagsView do
  @moduledoc false
  use LinkhutWeb, :view

  import XmlBuilder

  def render("get.xml", %{tags: tags}) do
    document(:tags, Enum.map(tags, fn t -> element(:tag, Map.take(t, [:tag, :count])) end))
    |> generate()
  end

  def render("get.json", %{tags: tags}) do
    Enum.reduce(tags, %{}, fn %{tag: tag, count: count}, result -> Map.put(result, tag, count) end)
  end

  def render("delete.xml", _) do
    document(:result, %{code: "done"})
    |> generate()
  end

  def render("delete.json", _) do
    %{result_code: "done"}
  end

  def render("rename.xml", _) do
    document(:result, %{code: "done"})
    |> generate()
  end

  def render("rename.json", _) do
    %{result_code: "done"}
  end
end
