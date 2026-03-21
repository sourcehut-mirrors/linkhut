defmodule Linkhut.Archiving.Steps do
  @moduledoc """
  Shared helpers for building archiving pipeline and crawler step entries.

  Step details are stored as structured maps with a `"msg"` key identifying
  the message type and additional keys for interpolation parameters. This
  enables i18n via gettext while keeping details machine-readable.
  """

  alias Linkhut.Repo

  require Logger

  @doc """
  Appends a step entry to an archive's steps list.

  Accepts an optional `at` datetime; defaults to `DateTime.utc_now()`.
  """
  def append_step(steps, step, detail, opts \\ []) do
    (steps || []) ++ [build_entry(step, detail, opts)]
  end

  @doc """
  Atomically appends a step to a crawl_run's steps array.
  Uses raw SQL to bypass optimistic locking. Defensive — never crashes.
  """
  def append_to_crawl_run(crawl_run_id, step, detail, opts \\ [])
  def append_to_crawl_run(nil, _step, _detail, _opts), do: :ok

  def append_to_crawl_run(crawl_run_id, step, detail, opts) do
    entry =
      build_entry(step, detail, opts)
      |> maybe_put("snapshot_id", opts[:snapshot_id])
      |> maybe_put("source", opts[:source])

    Repo.query!(
      "UPDATE crawl_runs SET steps = array_append(steps, $2::jsonb), updated_at = NOW() WHERE id = $1",
      [crawl_run_id, entry]
    )

    :ok
  rescue
    error ->
      Logger.warning("Failed to append step to crawl_run #{crawl_run_id}: #{inspect(error)}")
      :error
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
