defmodule Linkhut.Search.Context do
  @moduledoc """
  A search context reduces the universe of links that a search query is evaluated against.
  """

  @type t() :: %__MODULE__{
          from: String.t(),
          tagged_with: [String.t()],
          visible_as: String.t()
        }

  defstruct [:from, :tagged_with, :visible_as]
end
