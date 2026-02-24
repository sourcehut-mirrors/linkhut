defmodule LinkhutWeb.Breadcrumb do
  @moduledoc """
  Represents navigation breadcrumb segments for the page header.

  Templates render this struct instead of `Linkhut.Search.Context` directly,
  keeping layout rendering independent of the domain-level search scoping model.
  """

  defstruct [:user, :url, :title, tags: []]

  @type t() :: %__MODULE__{
          user: Linkhut.Accounts.User.t() | nil,
          url: String.t() | nil,
          tags: [String.t()],
          title: :recent | :popular | :unread | nil
        }

  @doc """
  Builds a breadcrumb from a `Linkhut.Search.Context` struct.
  """
  @spec from_context(Linkhut.Search.Context.t(), keyword()) :: t()
  def from_context(%Linkhut.Search.Context{} = context, opts \\ []) do
    %__MODULE__{
      user: context.from,
      url: context.url,
      tags: context.tagged_with,
      title: opts[:title]
    }
  end
end
