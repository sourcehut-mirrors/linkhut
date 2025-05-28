defmodule LinkhutWeb.Api.TagsXML do
  use LinkhutWeb, :xml

  import XmlBuilder

  def get(%{tags: tags}) do
    document(:tags, Enum.map(tags, fn t -> element(:tag, Map.take(t, [:tag, :count])) end))
    |> generate()
  end

  def done(_) do
    document(:result, %{code: "done"})
    |> generate()
  end
end
