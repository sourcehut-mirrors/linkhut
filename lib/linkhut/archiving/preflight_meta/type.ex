defmodule Linkhut.Archiving.PreflightMeta.Type do
  @moduledoc """
  Custom Ecto type that transparently serializes PreflightMeta structs
  to string-keyed maps for JSONB storage and deserializes them on load.
  """

  use Ecto.Type

  alias Linkhut.Archiving.PreflightMeta

  @impl true
  def type, do: :map

  @impl true
  def cast(%PreflightMeta{} = meta), do: {:ok, meta}
  def cast(meta) when is_map(meta), do: {:ok, PreflightMeta.from_map(meta)}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  @impl true
  def dump(%PreflightMeta{} = meta), do: {:ok, PreflightMeta.to_map(meta)}
  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  @impl true
  def load(meta) when is_map(meta), do: {:ok, PreflightMeta.from_map(meta)}
  def load(nil), do: {:ok, nil}
  def load(_), do: :error
end
