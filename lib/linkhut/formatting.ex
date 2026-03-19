defmodule Linkhut.Formatting do
  @moduledoc "Shared formatting utilities."

  @doc """
  Formats a file size in bytes to a human-readable string.

  Returns "Unknown" for nil.

  ## Examples

      iex> Linkhut.Formatting.format_bytes(nil)
      "Unknown"

      iex> Linkhut.Formatting.format_bytes(500)
      "500 bytes"

      iex> Linkhut.Formatting.format_bytes(2048)
      "2.0 KB"

      iex> Linkhut.Formatting.format_bytes(5_242_880)
      "5.0 MB"
  """
  def format_bytes(nil), do: "Unknown"

  def format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} bytes"
    end
  end

  @doc """
  Returns the human-readable display name for a crawler type string.

  ## Examples

      iex> Linkhut.Formatting.crawler_display_name("singlefile")
      "Web page"

      iex> Linkhut.Formatting.crawler_display_name("httpfetch")
      "File"

      iex> Linkhut.Formatting.crawler_display_name("wayback")
      "Wayback Machine"
  """
  def crawler_display_name("singlefile"), do: "Web page"
  def crawler_display_name("httpfetch"), do: "File"
  def crawler_display_name("wget"), do: "Wget"
  def crawler_display_name("wayback"), do: "Wayback Machine"
  def crawler_display_name(type), do: String.capitalize(type)

  def format_display_name("webpage"), do: "Webpage"
  def format_display_name("pdf"), do: "PDF"
  def format_display_name("text"), do: "Text"
  def format_display_name("reference"), do: "Reference"
  def format_display_name(format), do: String.capitalize(format)

  def source_display_name("singlefile"), do: "SingleFile"
  def source_display_name("httpfetch"), do: "HTTP Fetch"
  def source_display_name("wayback"), do: "Wayback Machine"
  def source_display_name("upload"), do: "Upload"
  def source_display_name(source), do: String.capitalize(source)
end
