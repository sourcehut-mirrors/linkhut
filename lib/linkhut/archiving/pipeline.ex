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
  Runs the full archiving pipeline for the given crawl run.

  1. Validates URL (SSRF check)
  2. Preflight request to get content_type, final_url, status
  3. SSRF check on final_url
  4. Selects eligible crawlers via can_handle?/2
  5. Atomically dispatches crawler jobs + creates pending snapshots

  Always-dispatch crawlers (third-party) are selected before preflight
  and dispatched alongside target crawlers. Not-archivable outcomes
  (invalid URL, unsupported scheme, no eligible crawlers, file too large)
  are finalized as `:not_archivable` — no retries.

  Options:
    - `:recrawl` - boolean, whether this is a re-crawl attempt
  """
  @spec run(CrawlRun.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%CrawlRun{} = crawl_run, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    crawl_run = maybe_record_retry(crawl_run, attempt)

    all_crawlers =
      Linkhut.Config.archiving(:crawlers, [])
      |> filter_by_types(Keyword.get(opts, :only_types))

    {target_crawlers, always_dispatch} = split_by_dispatch_phase(all_crawlers)

    # Select always-dispatch crawlers early (before preflight).
    always_eligible = select_always_dispatch(crawl_run.url, always_dispatch)

    with {:ok, crawl_run} <- validate_url(crawl_run),
         {:ok, preflight_meta, crawl_run} <- run_preflight(crawl_run, target_crawlers),
         {:ok, crawl_run} <- validate_final_url(crawl_run) do
      target_eligible =
        select_crawlers_from(
          crawl_run.final_url || crawl_run.url,
          preflight_meta,
          target_crawlers
        )

      dispatch_or_finalize(crawl_run, target_eligible ++ always_eligible, opts)
    else
      {:error, reason, crawl_run} ->
        handle_error(crawl_run, reason, always_eligible, opts)
    end
  end

  defp handle_error(crawl_run, reason, always_eligible, opts) do
    if Helpers.not_archivable?(reason) do
      FailureHandler.finalize_not_archivable(crawl_run, reason, opts)
    else
      dispatch_or_fail(crawl_run, reason, always_eligible, opts)
    end
  end

  defp dispatch_or_fail(crawl_run, reason, [_ | _] = crawlers, opts) do
    crawl_run = record_validation_failure(crawl_run, reason)
    FailureHandler.dispatch_and_finalize(crawl_run, crawlers, opts)
  end

  defp dispatch_or_fail(crawl_run, reason, [], opts) do
    FailureHandler.finalize_failure(crawl_run, reason, opts)
  end

  defp dispatch_or_finalize(crawl_run, [], opts) do
    FailureHandler.finalize_not_archivable(crawl_run, :no_eligible_crawlers, opts)
  end

  defp dispatch_or_finalize(crawl_run, crawlers, opts) do
    FailureHandler.dispatch_and_finalize(crawl_run, crawlers, opts)
  end

  # Runs the preflight pipeline for target_url crawlers.
  # When no target crawlers exist, skips the HTTP request entirely.
  defp run_preflight(crawl_run, [] = _target_crawlers) do
    {:ok, nil, crawl_run}
  end

  defp run_preflight(crawl_run, target_crawlers) when is_list(target_crawlers) do
    case Preflight.run(crawl_run) do
      {:ok, preflight_meta, crawl_run} -> {:ok, preflight_meta, crawl_run}
      {:error, reason, crawl_run} -> {:error, reason, crawl_run}
    end
  end

  defp record_validation_failure(crawl_run, reason) do
    Helpers.update_crawl_run_best_effort(crawl_run, %{
      steps:
        Steps.append_step(crawl_run.steps, "validation_failed", %{
          "msg" => "validation_failed",
          "error" => inspect(reason)
        })
    })
  end

  defp split_by_dispatch_phase(crawlers) do
    Enum.split_with(crawlers, &(&1.network_access() == :target_url))
  end

  defp select_always_dispatch(url, crawlers) do
    Enum.filter(crawlers, fn module -> module.can_handle?(url, nil) end)
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

  defp filter_by_types(crawlers, nil), do: crawlers

  defp filter_by_types(crawlers, types) when is_list(types) do
    type_set = MapSet.new(types)
    Enum.filter(crawlers, &MapSet.member?(type_set, &1.source_type()))
  end
end
