defmodule LinkhutWeb.SnapshotHTML do
  use LinkhutWeb, :html

  embed_templates "snapshot_html/*"

  @doc """
  Formats a file size in bytes to a human-readable format.
  """
  def format_file_size(nil), do: "Unknown"

  def format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} bytes"
    end
  end

  @doc """
  Formats a datetime for display in the snapshot metadata.
  """
  def format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> Date.to_string()
  end

  def format_datetime(_), do: "Unknown"

  @doc """
  Formats processing time from milliseconds to a readable format.
  """
  def format_processing_time(nil), do: "Unknown"

  def format_processing_time(ms) when is_integer(ms) do
    cond do
      ms >= 60_000 -> "#{Float.round(ms / 60_000, 1)} min"
      ms >= 1_000 -> "#{Float.round(ms / 1_000, 1)} sec"
      true -> "#{ms} ms"
    end
  end

  @doc """
  Returns the display name for a crawler type.
  """
  def crawler_display_name("singlefile"), do: "SingleFile"
  def crawler_display_name("wget"), do: "Wget"
  def crawler_display_name(type), do: String.capitalize(type)
end
