defmodule Linkhut.Dump do
  @moduledoc """
  Module for importing and exporting links
  """

  alias Linkhut.Dump.HTMLParser
  alias Linkhut.Links

  @type success :: {:ok, Linkhut.Links.link()}
  @type failure :: {:error, String.t() | %Ecto.Changeset{}}

  @spec import(Linkhut.Accounts.user(), String.t()) :: [success | failure]
  def import(user, document) do
    {:ok, bookmarks} = HTMLParser.parse_document(document)

    bookmarks
    |> Enum.map(&save(user, &1))
  end

  def export(user) do
    Links.all(user)
  end

  defp save(user, {:ok, attrs}) do
    Links.create_link(user, attrs)
  end

  defp save(_, {:error, msg}) do
    {:error, msg}
  end
end
