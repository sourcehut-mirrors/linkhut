defmodule Linkhut.Config do
  @moduledoc false

  @spec archiving(atom(), any()) :: any()
  def archiving(key, default \\ nil) do
    :linkhut
    |> Application.get_env(Linkhut.Archiving, [])
    |> Keyword.get(key, default)
  end

  @spec mail(atom(), any()) :: any()
  def mail(key, default \\ nil) do
    :linkhut
    |> Application.get_env(Linkhut.Mail, [])
    |> Keyword.get(key, default)
  end

  @spec ifttt(atom(), any()) :: any()
  def ifttt(key, default \\ nil) do
    :linkhut
    |> Application.get_env(Linkhut.IFTTT, [])
    |> Keyword.get(key, default)
  end

  @spec prometheus(atom(), any()) :: any()
  def prometheus(key, default \\ nil) do
    :linkhut
    |> Application.get_env(Linkhut.Prometheus, [])
    |> Keyword.get(key, default)
  end
end
