defmodule Linkhut.Search.Context do
  @moduledoc """
  A search context reduces the universe of links that a search query is evaluated against.
  """
  alias Linkhut.Accounts.User

  @type t() :: %__MODULE__{
          user: %User{},
          tags: [String.t()],
          issuer: %User{}
        }

  defstruct [:user, :tags, :issuer]
end
