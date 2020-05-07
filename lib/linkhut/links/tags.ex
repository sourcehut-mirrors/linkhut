defmodule Linkhut.Links.Tags do
  @moduledoc false

  @behaviour Ecto.Type

  @impl true
  def type, do: {:array, :string}

  @impl true
  def cast(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.split(~r{[, ]}, trim: true)
    |> cast
  end

  @impl true
  def cast(tags) when is_list(tags) do
    if Enum.all?(tags, &String.valid?/1) do
      {:ok, tags}
    else
      :error
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

  @impl true
  def equal?(term1, term2), do: term1 == term2

  @impl true
  def embed_as(_), do: :self
end
