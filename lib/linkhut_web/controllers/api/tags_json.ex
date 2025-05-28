defmodule LinkhutWeb.Api.TagsJSON do
  use LinkhutWeb, :json

  def get(%{tags: tags}) do
    Enum.reduce(tags, %{}, fn %{tag: tag, count: count}, result -> Map.put(result, tag, count) end)
  end

  def done(_) do
    %{result_code: "done"}
  end
end
