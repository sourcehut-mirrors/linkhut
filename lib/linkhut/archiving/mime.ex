defmodule Linkhut.Archiving.MIME do
  @moduledoc """
  Utility functions relating to MIME media types supported for archiving.

  This module intentionally models Linkhut archive formats rather than the
  entire MIME type registry.
  """

  @type archive_format :: String.t()
  @type group :: :webpage | :pdf | :text | :json | :image
  @type media_type :: String.t()

  @groups %{
    webpage: [
      "text/html",
      "application/xhtml+xml"
    ],
    pdf: [
      "application/pdf"
    ],
    text: [
      "text/css",
      "text/csv",
      "text/markdown",
      "text/plain",
      "text/xml",
      "application/xml"
    ],
    json: [
      "application/json",
      "application/ld+json"
    ],
    image: [
      "image/gif",
      "image/jpeg",
      "image/png",
      "image/webp"
    ]
  }

  @format_by_group %{
    webpage: "webpage",
    pdf: "pdf",
    text: "text",
    json: "json",
    image: "image"
  }

  @doc """
  Returns all archive media type groups.
  """
  @spec groups() :: %{group() => [media_type()]}
  def groups, do: @groups

  @doc """
  Returns all media types supported for archiving.
  """
  @spec types() :: [media_type()]
  def types do
    @groups
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc """
  Returns the media types for a given group.
  """
  @spec types(group() | [group()]) :: [media_type()]
  def types(group) when is_atom(group), do: Map.get(@groups, group, [])
  def types(groups) when is_list(groups), do: Enum.flat_map(groups, &types/1)

  @doc """
  Returns the archive group for a media type.
  """
  @spec group(media_type() | nil) :: group() | nil
  def group(nil), do: nil

  def group(media_type) when is_binary(media_type) do
    cond do
      media_type in types(:image) -> :image
      media_type in types(:json) -> :json
      media_type in types(:pdf) -> :pdf
      media_type in types(:webpage) -> :webpage
      compatible_with?(media_type, :text) -> :text
      true -> nil
    end
  end

  @doc """
  Returns the supported formats.
  """
  @spec formats() :: [archive_format()]
  def formats do
    groups()
    |> Map.keys()
    |> Enum.map(&Map.fetch!(@format_by_group, &1))
  end

  @doc """
  Returns the archive format for a media type.

      iex> Linkhut.MIME.format_from_content_type("text/html")
      {:ok, "webpage"}

      iex> Linkhut.MIME.format_from_content_type("image/png")
      {:ok, "image"}

  """
  @spec format_from_content_type(media_type() | nil) ::
          {:ok, archive_format()} | {:error, :unsupported_format}
  def format_from_content_type(content_type) do
    case group(content_type) do
      nil -> {:error, :unsupported_format}
      group -> {:ok, Map.fetch!(@format_by_group, group)}
    end
  end

  @doc """
  Returns whether a media type is supported as a webpage.
  """
  @spec webpage?(media_type() | nil) :: boolean()
  def webpage?(media_type), do: group(media_type) == :webpage

  @doc """
  Returns the MIME type detected by libmagic for `file_path`.
  """
  @spec detect(Path.t()) :: {:ok, media_type()} | {:error, term()}
  def detect(file_path) when is_binary(file_path) do
    case GenMagic.Server.perform(:gen_magic, file_path) do
      {:ok, %{mime_type: mime_type}} -> {:ok, mime_type}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns whether a media type is compatible with a given group.
  """
  @spec compatible_with?(media_type(), group()) :: boolean()
  def compatible_with?(content_type, group)

  def compatible_with?("text/" <> _, :text), do: true

  def compatible_with?(detected_type, group) do
    Enum.any?(types(group), &compatible_with_type?(&1, detected_type))
  end

  defp compatible_with_type?("text/" <> _, "text/" <> _), do: true
  defp compatible_with_type?("application/xml", "text/xml"), do: true
  defp compatible_with_type?("text/xml", "application/xml"), do: true
  defp compatible_with_type?(expected_type, detected_type), do: expected_type == detected_type
end
