defmodule Linkhut.Config do
  @moduledoc false

  @spec archiving(atom(), any()) :: any()
  def archiving(key, default \\ nil), do: get(Linkhut.Archiving, key, default)

  @spec mail(atom(), any()) :: any()
  def mail(key, default \\ nil), do: get(Linkhut.Mail, key, default)

  @spec ifttt(atom(), any()) :: any()
  def ifttt(key, default \\ nil), do: get(Linkhut.IFTTT, key, default)

  @spec moderation(atom(), any()) :: any()
  def moderation(key, default \\ nil), do: get(Linkhut.Moderation, key, default)

  @spec prometheus(atom(), any()) :: any()
  def prometheus(key, default \\ nil), do: get(Linkhut.Prometheus, key, default)

  @doc """
  Returns the full config keyword list for a namespace, with any
  per-process overrides applied on top of the Application env.
  """
  @spec all(module()) :: keyword()
  def all(namespace) do
    base = Application.get_env(:linkhut, namespace, [])
    overrides = collect_overrides(namespace)
    Keyword.merge(base, overrides)
  end

  @doc false
  @spec put_override(module(), atom(), any()) :: :ok
  def put_override(namespace, key, value) do
    overrides = Process.get(:linkhut_config_overrides, %{})
    Process.put(:linkhut_config_overrides, Map.put(overrides, {namespace, key}, value))
    :ok
  end

  # Per-process overrides allow tests to use async: true by avoiding
  # global Application.put_env. See put_override/3.
  defp get(namespace, key, default) do
    all(namespace) |> Keyword.get(key, default)
  end

  defp collect_overrides(namespace) do
    caller_overrides =
      Process.get(:"$callers", [])
      |> Enum.reduce([], fn pid, acc ->
        with {:dictionary, dict} <- Process.info(pid, :dictionary),
             overrides when is_map(overrides) <- Keyword.get(dict, :linkhut_config_overrides) do
          acc ++ extract_ns_overrides(overrides, namespace)
        else
          _ -> acc
        end
      end)

    current = extract_ns_overrides(Process.get(:linkhut_config_overrides), namespace)
    Keyword.merge(caller_overrides, current)
  end

  defp extract_ns_overrides(nil, _namespace), do: []

  defp extract_ns_overrides(overrides, namespace) do
    for {{^namespace, key}, value} <- overrides, do: {key, value}
  end
end
