defmodule Linkhut.ConfigHelpers do
  @moduledoc false

  @doc """
  Sets a per-process config override for the given namespace and key.

  Overrides are stored in the process dictionary and propagate to child
  processes spawned via `Task.async` (which inherits `$callers`).
  Cleanup is automatic when the test process exits.
  """
  def put_config(namespace, key, value) do
    Linkhut.Config.put_override(namespace, key, value)
  end
end
