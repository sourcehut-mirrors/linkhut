defmodule Linkhut.Links.Tags do
  @moduledoc false

  @behaviour Ecto.Type

  @unread_tag "unread"

  @impl true
  def type, do: {:array, :string}

  @impl true
  def cast(string) when is_binary(string) do
    string
    |> String.trim()
    |> String.split(~r{[, ]}, trim: true)
    |> Enum.dedup_by(fn x -> String.downcase(x) end)
    |> cast
  end

  @impl true
  def cast(tags) when is_list(tags) do
    if Enum.all?(tags, &valid?/1) do
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

  def unread, do: @unread_tag

  def is_unread?(tag) do
    tag
    |> String.downcase()
    |> (&(&1 == "unread" or &1 == "toread")).()
  end

  defp valid?(tag) do
    String.valid?(tag) && String.length(tag) <= 128 && not String.starts_with?(tag, "~") &&
      not String.starts_with?(tag, "-")
  end
end
