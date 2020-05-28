defmodule Linkhut.Search.Query do
  @moduledoc """
  A simple query definition.
  """

  alias Linkhut.Search.Term

  @type t() :: %__MODULE__{
          quotes: [String.t()],
          tags: [String.t()],
          users: [String.t()],
          words: String.t()
        }

  defstruct quotes: [], users: [], words: "", tags: []

  @spec query([Term.t()]) :: t()
  def query(terms) do
    terms
    |> Enum.group_by(&Term.type/1, &Term.value/1)
    |> new()
  end

  defp new(map) do
    %__MODULE__{
      quotes: if(q = map[:quote], do: q, else: []),
      tags: if(t = map[:tag], do: t, else: []),
      users: if(u = map[:user], do: u, else: []),
      words: if(w = map[:word], do: Enum.join(w, " "), else: "")
    }
  end
end
