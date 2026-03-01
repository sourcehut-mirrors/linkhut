defmodule Linkhut.Archiving.Pipeline.FailureHandler do
  @moduledoc """
  Encapsulates the pipeline's failure strategy: retry-aware state
  transitions, partial failure recording, and third-party fallback policy.
  """

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Steps}
  alias Linkhut.Archiving.Pipeline.{Dispatch, Helpers}

  @doc """
  Dispatches crawlers and finalizes on failure.
  """
  @spec dispatch_and_finalize(Archive.t(), [module()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def dispatch_and_finalize(archive, crawlers, opts) do
    case Dispatch.dispatch_crawlers(archive, crawlers, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason, archive} -> finalize_failure(archive, reason, opts)
    end
  end

  @doc """
  Attempts to dispatch fallback crawlers. If the crawler list is empty,
  finalizes the failure instead.
  """
  @spec maybe_dispatch_fallback(Archive.t(), [module()], term(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def maybe_dispatch_fallback(archive, [], reason, opts) do
    finalize_failure(archive, reason, opts)
  end

  def maybe_dispatch_fallback(archive, crawlers, reason, opts) do
    archive = record_partial_failure(archive, reason)
    dispatch_and_finalize(archive, crawlers, opts)
  end

  @doc """
  Finalizes a pipeline failure, recording the appropriate step.

  On the final attempt, sets the archive state to `:failed`. On
  non-final attempts, records the error but leaves the state unchanged
  so the archiver worker can retry.
  """
  @spec finalize_failure(Archive.t(), term(), keyword()) :: {:error, term()}
  def finalize_failure(archive, reason, opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    fatal? = Helpers.fatal?(reason)
    final_attempt? = fatal? or attempt >= max_attempts
    msg = if final_attempt?, do: "failed_final", else: "failed_will_retry"

    failed_detail = %{"msg" => msg, "error" => inspect(reason)}

    failed_detail =
      if fatal?,
        do: failed_detail,
        else: Map.merge(failed_detail, %{"attempt" => attempt, "max_attempts" => max_attempts})

    state_update =
      if final_attempt?,
        do: %{state: :failed, error: inspect(reason)},
        else: %{error: inspect(reason)}

    # Return value intentionally ignored — this is a best-effort DB write.
    # The pipeline's return value is determined by the original error reason.
    Helpers.update_archive_best_effort(
      archive,
      Map.put(state_update, :steps, Steps.append_step(archive.steps, "failed", failed_detail))
    )

    if final_attempt? and Keyword.get(opts, :recrawl, false) do
      Archiving.mark_old_archives_for_deletion(archive.link_id, exclude: [archive.id])
    end

    {:error, reason}
  end

  @doc """
  Records a partial failure step and returns the updated archive.
  """
  def record_partial_failure(archive, reason) do
    Helpers.update_archive_best_effort(archive, %{
      steps:
        Steps.append_step(archive.steps, "partial_failure", %{
          "msg" => "partial_failure",
          "error" => inspect(reason)
        })
    })
  end

  @doc """
  Returns true if the given failure reason allows dispatching to a
  third-party crawler (one that doesn't connect to the target URL).
  """
  def safe_after_failure?(:preflight_failed, :third_party), do: true
  def safe_after_failure?({:dns_failed, _}, :third_party), do: true
  def safe_after_failure?(_, _), do: false
end
