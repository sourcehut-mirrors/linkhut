defmodule Linkhut.Archiving.Format do
  @moduledoc "Display formatting for snapshot formats and sources"

  def format_display_name("webpage"), do: "Webpage"
  def format_display_name("pdf"), do: "PDF"
  def format_display_name("text"), do: "Text"
  def format_display_name("image"), do: "Image"
  def format_display_name("reference"), do: "External"
  def format_display_name(format), do: String.capitalize(format)

  @doc """
  Returns a sort key for format tab ordering.
  Local artifact formats sort before external/reference formats.
  """
  def format_sort_key("reference"), do: 1
  def format_sort_key(_), do: 0

  @doc """
  Returns the human-readable display name for a source type string.
  """
  def source_display_name("singlefile"), do: "SingleFile"
  def source_display_name("httpfetch"), do: "HTTP Fetch"
  def source_display_name("wayback"), do: "Wayback Machine"
  def source_display_name("upload"), do: "Upload"
  def source_display_name(source), do: String.capitalize(source)
end
