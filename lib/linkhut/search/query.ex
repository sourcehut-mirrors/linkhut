defmodule Linkhut.Search.Query do
  @moduledoc """
  A simple query definition.
  """

  alias Linkhut.Search.Term

  @type t() :: %__MODULE__{
                 users: [String.t()],
                 quotes: [String.t()],
                 words: [String.t()]
               }

  defstruct [
    :users, :quotes, :words
  ]

  def query(terms) do
    terms
    |> Enum.group_by(&Term.type/1, &Term.value/1)
  end

end
