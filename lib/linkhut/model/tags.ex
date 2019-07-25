defmodule Linkhut.Model.Tags do
  @behaviour Ecto.Type

  @impl true
  def type, do: {:array, :string}

  @impl true
  def cast(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.split([" ", ","])
    |> cast
  end

  @impl true
  def cast(tags) when is_list(tags) do
    cond do
      Enum.all?(tags, &is_binary(&1)) -> {:ok, tags}
      true -> :error
    end
  end

  @impl true
  def cast(_), do: :error

  @impl true
  def load(tags) when is_list(tags), do: {:ok, tags}

  @impl true
  def dump(tags) when is_list(tags), do: {:ok, tags}

  @impl true
  def dump(_), do: :error
end
