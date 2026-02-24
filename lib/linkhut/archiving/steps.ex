defmodule Linkhut.Archiving.Steps do
  @moduledoc """
  Shared helpers for building archiving pipeline and crawler step entries.

  Step details are stored as structured maps with a `"msg"` key identifying
  the message type and additional keys for interpolation parameters. This
  enables i18n via gettext while keeping details machine-readable.
  """

  @doc """
  Appends a step entry to an archive's steps list.

  Accepts an optional `at` datetime; defaults to `DateTime.utc_now()`.
  """
  def append_step(steps, step, detail, opts \\ []) do
    (steps || []) ++ [build_entry(step, detail, opts)]
  end

  @doc """
  Appends a step entry to a snapshot's crawl_info steps list.
  """
  def add_crawl_step(crawl_info, step, detail \\ nil) do
    steps = get_in(crawl_info || %{}, ["steps"]) || []
    Map.put(crawl_info || %{}, "steps", steps ++ [build_entry(step, detail, [])])
  end

  defp build_entry(step, nil, opts) do
    %{"step" => step, "at" => format_at(opts)}
  end

  defp build_entry(step, detail, opts) when is_map(detail) do
    %{"step" => step, "detail" => detail, "at" => format_at(opts)}
  end

  defp format_at(opts) do
    opts
    |> Keyword.get(:at, DateTime.utc_now())
    |> DateTime.to_iso8601()
  end
end
