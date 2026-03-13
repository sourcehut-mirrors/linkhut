defmodule Linkhut.DataTransfer.Parser do
  @moduledoc """
  Behaviour for bookmark file format parsers.
  """

  @type bookmark :: {:ok, map()} | {:error, String.t()}

  @callback parse_document(binary()) :: {:ok, [bookmark()]} | {:error, term()}
  @callback can_parse?(binary()) :: boolean()
end
