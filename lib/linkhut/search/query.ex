defmodule Linkhut.Search.Query do
  @moduledoc """
  A simple query definition.
  """

  alias Linkhut.Search.Term

  @type t() :: %__MODULE__{
          quotes: [String.t()],
          tags: [String.t()],
          users: [String.t()],
          words: [String.t()]
        }

  defstruct [
    :quotes,
    :users,
    :words,
    :tags
  ]

  @spec query([Term.t()]) :: t()
  def query(terms) do
    terms
    |> Enum.group_by(&Term.type/1, &Term.value/1)
    |> new()
  end

  defp new(map) do
    %__MODULE__{
      quotes: map[:quote],
      tags: map[:tag],
      users: map[:user],
      words: map[:word]
    }
  end
end
