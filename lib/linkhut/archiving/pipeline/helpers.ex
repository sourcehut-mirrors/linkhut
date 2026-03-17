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
  Returns true if the error reason is fatal (no retries, no third-party fallback).
  """
  def fatal?(:invalid_url), do: true
  def fatal?({:unsupported_scheme, _}), do: true
  def fatal?(:no_eligible_crawlers), do: true
  def fatal?(_), do: false
end
