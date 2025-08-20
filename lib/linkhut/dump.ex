defmodule Linkhut.Dump do
  @moduledoc """
  Module for importing and exporting links
  """

  alias Linkhut.Dump.HTMLParser
  alias Linkhut.Links

  @type success :: {:ok, Linkhut.Links.Link.t()}
  @type failure :: {:error, String.t() | %Ecto.Changeset{}}

  @spec import(Linkhut.Accounts.User.t(), String.t(), map()) :: [success | failure]
  def import(user, document, overrides) do
    {:ok, bookmarks} = HTMLParser.parse_document(document)

    bookmarks
    |> Enum.map(&save(user, &1, overrides))
  end

  def export(user) do
    Links.all(user)
  end

  defp save(user, {:ok, attrs}, %{"is_private" => "true"}) do
    Links.create_link(user, Map.replace(attrs, :is_private, true))
  end

  defp save(user, {:ok, attrs}, _overrides) do
    Links.create_link(user, attrs)
  end

  defp save(_, {:error, msg}, _overrides) do
    {:error, msg}
  end
end
