defmodule Linkhut.Archiving.Pipeline do
  @moduledoc """
  Orchestrates the archiving pipeline from URL validation through
  crawler dispatch. Called by the Archiver worker.
  """

  alias Linkhut.Archiving.{CrawlRun, Steps}
  alias Linkhut.Archiving.Pipeline.{FailureHandler, Helpers, Preflight}

  defp maybe_record_retry(crawl_run, 1), do: crawl_run

  defp maybe_record_retry(crawl_run, attempt) do
    Helpers.update_crawl_run_best_effort(crawl_run, %{
      steps:
        Steps.append_step(crawl_run.steps, "retry", %{
          "msg" => "retry",
          "attempt" => attempt
        })
    })
  end

  @doc """
  Runs the full archiving pipeline for the given archive.

  1. Validates URL (SSRF check)
  2. Preflight request to get content_type, final_url, status
  3. SSRF check on final_url
  4. Updates archive with preflight_meta
  5. Selects eligible crawlers via can_handle?/2
  6. Atomically dispatches crawler jobs + creates pending snapshots

  ## Flow

      run/2
        -> run_preflight/2  => {:ok, meta | nil, archive, eligible}
                             | {:error, reason, archive}
                             | {:fatal, reason, archive}
        -> classify_outcome/2 => {:dispatch, ...} | {:fallback, ...} | {:fail, ...}
        -> execute_outcome/2 => {:ok, result} | {:error, reason}

  Options:
    - `:recrawl` - boolean, whether this is a re-crawl attempt
  """
  @spec run(CrawlRun.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%CrawlRun{} = crawl_run, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    crawl_run = maybe_record_retry(crawl_run, attempt)

    all_crawlers = Linkhut.Config.archiving(:crawlers, [])
    {target_crawlers, third_party_crawlers} = partition_by_network_access(all_crawlers)

    run_preflight(crawl_run, target_crawlers)
    |> classify_outcome(third_party_crawlers)
    |> execute_outcome(opts)
  end

  defp classify_outcome({:ok, _meta, crawl_run, eligible}, _tp) when eligible != [] do
    {:dispatch, crawl_run, eligible}
  end

  # preflight_meta is nil when no target_url crawlers are configured
  # (run_preflight skips the HTTP request entirely in that case).
  defp classify_outcome({:ok, preflight_meta, crawl_run, _eligible}, tp) do
    status = if preflight_meta, do: preflight_meta.status

    if is_integer(status) and status >= 400 do
      {:fallback, crawl_run, select_third_party(crawl_run.url, tp), {:http_error, status}}
    else
      {:fail, crawl_run, :no_eligible_crawlers}
    end
  end

  defp classify_outcome({:error, reason, crawl_run}, tp) do
    safe_tp =
      select_third_party(crawl_run.url, tp)
      |> Enum.filter(&FailureHandler.safe_after_failure?(reason, crawler_network_access(&1)))

    {:fallback, crawl_run, safe_tp, reason}
  end

  defp classify_outcome({:fatal, reason, crawl_run}, _tp) do
    {:fail, crawl_run, reason}
  end

  defp execute_outcome({:dispatch, crawl_run, crawlers}, opts) do
    FailureHandler.dispatch_and_finalize(crawl_run, crawlers, opts)
  end

  defp execute_outcome({:fallback, crawl_run, crawlers, reason}, opts) do
    FailureHandler.maybe_dispatch_fallback(crawl_run, crawlers, reason, opts)
  end

  defp execute_outcome({:fail, crawl_run, reason}, opts) do
    FailureHandler.finalize_failure(crawl_run, reason, opts)
  end

  # Runs the preflight pipeline for target_url crawlers.
  # Returns {:ok, preflight_meta, crawl_run, eligible_crawlers},
  #         {:error, reason, crawl_run} for recoverable failures,
  #         {:fatal, reason, crawl_run} for fatal failures.
  defp run_preflight(crawl_run, [] = _target_crawlers) do
    case validate_url(crawl_run) do
      {:ok, crawl_run} -> {:ok, nil, crawl_run, []}
      {:error, reason, crawl_run} -> classify_preflight_error(reason, crawl_run)
    end
  end

  defp run_preflight(crawl_run, target_crawlers) do
    with {:ok, crawl_run} <- validate_url(crawl_run),
         {:ok, preflight_meta, crawl_run} <- Preflight.run(crawl_run),
         {:ok, crawl_run} <- validate_final_url(crawl_run) do
      eligible =
        select_crawlers_from(
          crawl_run.final_url || crawl_run.url,
          preflight_meta,
          target_crawlers
        )

      {:ok, preflight_meta, crawl_run, eligible}
    else
      {:error, reason, crawl_run} -> classify_preflight_error(reason, crawl_run)
    end
  end

  defp classify_preflight_error(reason, crawl_run) do
    if Helpers.fatal?(reason),
      do: {:fatal, reason, crawl_run},
      else: {:error, reason, crawl_run}
  end

  # Passes nil as preflight_meta since third-party crawlers don't connect
  # to the target URL and therefore don't need preflight data.
  defp select_third_party(url, crawlers) do
    Enum.filter(crawlers, fn module -> module.can_handle?(url, nil) end)
  end

  defp crawler_network_access(module), do: module.network_access()

  defp partition_by_network_access(crawlers) do
    Enum.split_with(crawlers, &(crawler_network_access(&1) == :target_url))
  end

  defp validate_url(%CrawlRun{url: url} = crawl_run), do: check_host(url, crawl_run)

  defp validate_final_url(%CrawlRun{final_url: nil} = crawl_run), do: {:ok, crawl_run}
  defp validate_final_url(%CrawlRun{final_url: url} = crawl_run), do: check_host(url, crawl_run)

  defp check_host(url, crawl_run) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        case Linkhut.Network.check_address(host) do
          :ok -> {:ok, crawl_run}
          {:error, {:dns_failed, _} = reason} -> {:error, reason, crawl_run}
          {:error, reason} -> {:error, {:reserved_address, reason}, crawl_run}
        end

      _ ->
        {:error, :invalid_url, crawl_run}
    end
  end

  defp select_crawlers_from(url, preflight_meta, crawlers) do
    Enum.filter(crawlers, fn module -> module.can_handle?(url, preflight_meta) end)
  end
end
