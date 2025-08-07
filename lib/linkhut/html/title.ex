defmodule Linkhut.Html.Title do
  @moduledoc """
  Utilities for extracting the best possible title from an HTML tree.
  """

  @type html_tree :: tuple() | list()

  @doc """
  Returns the most appropriate title from the HTML.

  Preference order:
  1. `og:title` meta tag
  2. `<title>` tag
  3. `<h1>` tag
  """
  @spec title(html_tree | String.t()) :: binary()
  def title(html) when is_binary(html) do
    with {:ok, tree} <- Floki.parse_document(html) do
      title(tree)
    else
      _ -> ""
    end
  end

  def title(tree) do
    with title when title == "" <- og_title(tree),
         title when title == "" <- tag_title(tree) do
      hdg_title(tree)
    else
      title -> title
    end
  end

  @doc "Extracts the title from the `<title>` tag inside `<head>`."
  @spec tag_title(html_tree) :: binary()
  def tag_title(tree) do
    tree
    |> Floki.find("head title")
    |> List.first("")
    |> clean_title()
  end

  @doc "Extracts the Open Graph `og:title` from meta tags."
  @spec og_title(html_tree) :: binary()
  def og_title(tree) do
    with meta <- Floki.find(tree, "meta[property='og:title']") |> List.first([""]),
         [content] <- Floki.attribute(meta, "content") do
      String.trim(content)
    else
      _ -> ""
    end
  end

  @doc "Extracts the title from the first `<h1>` tag."
  @spec hdg_title(html_tree) :: binary()
  def hdg_title(tree) do
    tree
    |> Floki.find("h1")
    |> List.first("")
    |> clean_title()
  end

  defp clean_title(""), do: ""
  defp clean_title(tree), do: tree |> Floki.text() |> String.trim()
end
