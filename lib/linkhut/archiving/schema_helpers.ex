defmodule Linkhut.Archiving.SchemaHelpers do
  @moduledoc """
  Shared changeset helpers for archiving schemas (Archive, Snapshot).
  """

  @doc """
  Normalizes JSON-stored map/array fields by converting atom keys to strings.
  Accepts a changeset and a list of field names to normalize.
  """
  def normalize_json_fields(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, cs ->
      case Ecto.Changeset.get_change(cs, field) do
        nil -> cs
        value -> Ecto.Changeset.put_change(cs, field, stringify_keys(value))
      end
    end)
  end

  defp stringify_keys(%{} = map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
