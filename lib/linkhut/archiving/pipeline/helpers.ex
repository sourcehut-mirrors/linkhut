defmodule Linkhut.Archiving.Pipeline.Helpers do
  @moduledoc """
  Shared utilities used by Pipeline sub-modules.
  """

  alias Linkhut.Archiving

  require Logger

  @doc """
  Updates a crawl run, logging and swallowing failures.

  Used for non-critical updates (step recording, retry markers) where
  the pipeline should continue even if the DB write fails.
  """
  def update_crawl_run_best_effort(crawl_run, attrs) do
    case Archiving.update_crawl_run(crawl_run, attrs) do
      {:ok, crawl_run} ->
        crawl_run

      {:error, changeset} ->
        Logger.warning("Failed to update crawl run #{crawl_run.id}: #{inspect(changeset.errors)}")

        crawl_run
    end
  end

  @doc """
  Returns true if the URL/content is fundamentally not archivable.
  These outcomes are permanent — retrying will never succeed.
  """
  def not_archivable?(:invalid_url), do: true
  def not_archivable?({:unsupported_scheme, _}), do: true
  def not_archivable?({:reserved_address, _}), do: true
  def not_archivable?(:no_eligible_crawlers), do: true
  def not_archivable?({:file_too_large, _}), do: true
  def not_archivable?(_), do: false

  @doc """
  Returns true if the error reason is fatal (no retries).
  """
  def fatal?({:http_error, 429}), do: false
  def fatal?({:http_error, status}) when status >= 400 and status < 500, do: true
  def fatal?(_), do: false
end
