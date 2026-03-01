defmodule Linkhut.Archiving.PreflightMeta do
  @moduledoc """
  Structured metadata from the preflight step.

  Used throughout the pipeline, serialized to string-keyed maps for
  Oban job args and DB storage. Add new fields here when new preflight
  schemes require additional metadata.
  """

  @fields [:scheme, :content_type, :content_length, :final_url, :status]

  defstruct @fields

  @type t() :: %__MODULE__{
          scheme: String.t() | nil,
          content_type: String.t() | nil,
          content_length: integer() | nil,
          final_url: String.t() | nil,
          status: integer() | nil
        }

  @doc """
  Converts a struct to a string-keyed map for Oban/JSON serialization.
  Returns nil for nil input.
  """
  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = meta) do
    meta |> Map.from_struct() |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc """
  Reconstructs struct from a string-keyed map (Oban args or DB read).
  Unknown keys are discarded. Returns nil for nil input.
  """
  def from_map(nil), do: nil

  def from_map(meta) when is_map(meta) do
    attrs =
      for field <- @fields,
          key = Atom.to_string(field),
          Map.has_key?(meta, key),
          do: {field, meta[key]}

    struct(__MODULE__, attrs)
  end
end
