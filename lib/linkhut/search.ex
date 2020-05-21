defmodule Linkhut.Search do
  @moduledoc """
  The Search context.
  """

  alias Linkhut.Search.{Parser, Query}

  def parse(query_string) do
    Parser.parse(query_string)
  end
end
