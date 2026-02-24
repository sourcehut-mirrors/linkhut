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
end
