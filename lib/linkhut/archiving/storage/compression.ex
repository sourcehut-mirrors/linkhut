defmodule Linkhut.Archiving.Storage.Compression do
  @moduledoc """
  Shared compression logic for storage backends.

  Provides helpers to determine whether content should be compressed
  and to perform gzip compression when beneficial.
  """

  @compressible_types [
    # HTML / XML
    "text/html",
    "application/xhtml+xml",
    "application/xml",
    "text/xml",
    "application/atom+xml",
    "application/rss+xml",
    # Text
    "text/plain",
    "text/markdown",
    "text/css",
    "text/csv",
    # Script / data
    "text/javascript",
    "application/javascript",
    "application/json",
    "application/ld+json",
    # Other
    "application/rtf",
    "image/svg+xml"
  ]

  @doc "Returns the list of MIME types eligible for compression."
  def compressible_types, do: @compressible_types

  @doc """
  Returns true if the content described by `opts` should be compressed
  given the `compression` setting (`:gzip` or `:none`).
  """
  def should_compress?(compression, opts) do
    compression != :none and
      Keyword.get(opts, :content_type) in @compressible_types
  end

  @doc """
  Compresses data with gzip if the result is smaller than the original.

  Returns `{:compressed, data, size}` or `{:uncompressed, data, size}`.
  """
  def compress(data) when is_binary(data) do
    compressed = :zlib.gzip(data)

    if byte_size(compressed) < byte_size(data) do
      {:compressed, compressed, byte_size(compressed)}
    else
      {:uncompressed, data, byte_size(data)}
    end
  end
end
