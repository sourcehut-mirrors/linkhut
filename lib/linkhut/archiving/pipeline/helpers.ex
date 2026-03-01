defmodule Linkhut.Archiving.Pipeline.Helpers do
  @moduledoc """
  Shared utilities used by Pipeline sub-modules.
  """

  alias Linkhut.Archiving

  require Logger

  @doc """
  Updates an archive, logging and swallowing failures.

  Used for non-critical updates (step recording, retry markers) where
  the pipeline should continue even if the DB write fails.
  """
  def update_archive_best_effort(archive, attrs) do
    case Archiving.update_archive(archive, attrs) do
      {:ok, archive} ->
        archive

      {:error, changeset} ->
        Logger.warning("Failed to update archive #{archive.id}: #{inspect(changeset.errors)}")

        archive
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
