defmodule Linkhut.Archiving.Pipeline.FailureHandler do
  @moduledoc """
  Encapsulates the pipeline's failure strategy: retry-aware state
  transitions and not-archivable finalization.
  """

  alias Linkhut.Archiving.{CrawlRun, Steps}
  alias Linkhut.Archiving.Pipeline.{Dispatch, Helpers}

  @doc """
  Dispatches crawlers and finalizes on failure.
  """
  @spec dispatch_and_finalize(CrawlRun.t(), [module()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def dispatch_and_finalize(crawl_run, crawlers, opts) do
    case Dispatch.dispatch_crawlers(crawl_run, crawlers, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason, crawl_run} -> finalize_failure(crawl_run, reason, opts)
    end
  end

  @doc """
  Finalizes a crawl run as not archivable. The URL/content is fundamentally
  incompatible with archiving — retrying will never succeed.

  Sets state to `:not_archivable`, records the reason, and returns
  `{:ok, %{status: :not_archivable}}` so Oban treats it as success.
  """
  @spec finalize_not_archivable(CrawlRun.t(), term(), keyword()) ::
          {:ok, %{crawl_run: CrawlRun.t(), status: :not_archivable}}
  def finalize_not_archivable(crawl_run, reason, _opts) do
    reason_string = format_not_archivable_reason(reason)

    steps =
      Steps.append_step(crawl_run.steps, "not_archivable", %{
        "msg" => "not_archivable",
        "reason" => reason_string
      })

    crawl_run =
      Helpers.update_crawl_run_best_effort(crawl_run, %{
        state: :not_archivable,
        error: reason_string,
        steps: steps
      })

    {:ok, %{crawl_run: crawl_run, status: :not_archivable}}
  end

  @doc """
  Finalizes a pipeline failure, recording the appropriate step.

  On the final attempt, sets the crawl run state to `:failed`. On
  non-final attempts, records the error but leaves the state unchanged
  so the archiver worker can retry.
  """
  @spec finalize_failure(CrawlRun.t(), term(), keyword()) :: {:error, term()}
  def finalize_failure(crawl_run, reason, opts) do
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
    Helpers.update_crawl_run_best_effort(
      crawl_run,
      Map.put(state_update, :steps, Steps.append_step(crawl_run.steps, "failed", failed_detail))
    )

    {:error, reason}
  end

  defp format_not_archivable_reason(:invalid_url), do: "invalid_url"
  defp format_not_archivable_reason({:unsupported_scheme, s}), do: "unsupported_scheme:#{s}"
  defp format_not_archivable_reason({:reserved_address, _}), do: "reserved_address"
  defp format_not_archivable_reason(:no_eligible_crawlers), do: "no_eligible_crawlers"
  defp format_not_archivable_reason({:file_too_large, _}), do: "file_too_large"
  defp format_not_archivable_reason(reason), do: inspect(reason)
end
