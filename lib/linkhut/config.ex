defmodule Linkhut.Config do
  @moduledoc false
  defmodule Error do
    defexception [:message]
  end

  def get(key), do: get(key, nil)

  def get([key], default), do: get(key, default)

  def get([_ | _] = path, default) do
    case fetch(path) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def get(key, default) do
    Application.get_env(:linkhut, key, default)
  end

  def get!(key) do
    value = get(key, nil)

    if value == nil do
      raise(Error, message: "Missing configuration value: #{inspect(key)}")
    else
      value
    end
  end

  def fetch(key) when is_atom(key), do: fetch([key])

  def fetch([root_key | keys]) do
    Enum.reduce_while(keys, Application.fetch_env(:linkhut, root_key), fn
      key, {:ok, config} when is_map(config) or is_list(config) ->
        case Access.fetch(config, key) do
          :error ->
            {:halt, :error}

          value ->
            {:cont, value}
        end

      _key, _config ->
        {:halt, :error}
    end)
  end

  @spec ifttt() :: keyword()
  def ifttt() do
    get([Linkhut, :ifttt])
  end

  @spec ifttt(atom(), any()) :: any()
  def ifttt(key, value \\ nil) do
    ifttt()
    |> Keyword.get(key, value)
  end

  @spec mail() :: keyword()
  def mail() do
    get([Linkhut, :mail])
  end

  @spec mail(atom(), any()) :: any()
  def mail(key, value \\ nil) do
    mail()
    |> Keyword.get(key, value)
  end
end
