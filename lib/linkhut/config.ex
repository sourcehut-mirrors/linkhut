defmodule Linkhut.Config do
  @moduledoc false
  defmodule Error do
    defexception [:message]
  end

  @spec get(atom()) :: any()
  def get(key) when is_atom(key), do: get([key])

  @spec get(list(atom())) :: any()
  def get([root_key | keys]) do
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

  @spec get(atom() | list(atom())) :: any()
  def get(key), do: get(key, nil)

  @spec get(list(atom()), any()) :: any()
  def get([key], default), do: get(key, default)

  @spec get(list(atom()), any()) :: any()
  def get([_ | _] = path, default) do
    case get(path) do
      {:ok, value} -> value
      :error -> default
    end
  end

  @spec get(atom(), any()) :: any()
  def get(key, default) do
    Application.get_env(:linkhut, key, default)
  end

  @spec get!(atom() | list(atom())) :: any()
  def get!(key) do
    value = get(key, nil)

    if value == nil do
      raise(Error, message: "Missing configuration value: #{inspect(key)}")
    else
      value
    end
  end

  @spec ifttt() :: keyword()
  def ifttt() do
    get(:ifttt)
  end

  @spec ifttt(atom(), any()) :: any()
  def ifttt(key, value \\ nil) do
    ifttt()
    |> Keyword.get(key, value)
  end
end
