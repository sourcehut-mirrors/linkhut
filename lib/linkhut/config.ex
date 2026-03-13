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

  @doc false
  @spec put_override(module(), atom(), any()) :: :ok
  def put_override(namespace, key, value) do
    overrides = Process.get(:linkhut_config_overrides, %{})
    Process.put(:linkhut_config_overrides, Map.put(overrides, {namespace, key}, value))
    :ok
  end

  defp get(namespace, key, default) do
    case fetch_override(namespace, key) do
      {:ok, value} ->
        value

      :error ->
        :linkhut
        |> Application.get_env(namespace, [])
        |> Keyword.get(key, default)
    end
  end

  # Per-process overrides allow tests to use async: true by avoiding
  # global Application.put_env. See put_override/3.
  defp fetch_override(namespace, key) do
    with :error <- fetch_from_dict(Process.get(:linkhut_config_overrides), namespace, key) do
      fetch_from_callers(namespace, key)
    end
  end

  defp fetch_from_dict(nil, _namespace, _key), do: :error
  defp fetch_from_dict(overrides, namespace, key), do: Map.fetch(overrides, {namespace, key})

  defp fetch_from_callers(namespace, key) do
    Process.get(:"$callers", [])
    |> Enum.find_value(:error, fn pid ->
      with {:dictionary, dict} <- Process.info(pid, :dictionary),
           overrides when is_map(overrides) <- Keyword.get(dict, :linkhut_config_overrides),
           {:ok, _} = hit <- Map.fetch(overrides, {namespace, key}) do
        hit
      else
        _ -> nil
      end
    end)
  end
end
