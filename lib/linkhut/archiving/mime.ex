defmodule Linkhut.Archiving.MIME do
  @moduledoc """
  Utility functions relating to MIME media types supported for archiving.

  This module intentionally models Linkhut archive formats rather than the
  entire MIME type registry.
  """

  @type archive_format :: String.t()
  @type media_type :: String.t()

  @types %{
    "webpage" => [
      "text/html",
      "application/xhtml+xml"
    ],
    "pdf" => [
      "application/pdf"
    ],
    "text" => [
      "text/css",
      "text/csv",
      "text/markdown",
      "text/plain",
      "text/xml",
      "application/xml"
    ],
    "json" => [
      "application/json",
      "application/ld+json"
    ],
    "image" => [
      "image/gif",
      "image/jpeg",
      "image/png",
      "image/webp"
    ]
  }

  @doc """
  Returns all media types supported for archiving.
  """
  @spec types() :: [media_type()]
  def types, do: @types |> Map.values() |> List.flatten()

  @doc """
  Returns the archive format for a media type, or `nil` if it has none.
  """
  @spec format(media_type() | nil) :: archive_format() | nil
  def format(media_type) do
    Enum.find_value(@types, fn {format, types} -> if media_type in types, do: format end)
  end

  @doc """
  Returns the media type in a `Content-Type` header value, lowercased and
  without its parameters.
  """
  @spec media_type(String.t() | nil) :: media_type() | nil
  def media_type(nil), do: nil

  def media_type(content_type) do
    content_type
    |> String.split(";")
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

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
end
