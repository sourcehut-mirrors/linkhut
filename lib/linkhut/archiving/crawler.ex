defmodule Linkhut.Archiving.Crawler do
  @moduledoc """
  Defines the behavior for a crawler.
  """

  @callback fetch(integer, integer, String.t()) :: {:ok, map()} | {:error, map()}
end
