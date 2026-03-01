defmodule Linkhut.Archiving.Pipeline do
  @moduledoc """
  Orchestrates the archiving pipeline from URL validation through
  crawler dispatch. Called by the Archiver worker.
  """

  alias Linkhut.Archiving.{Archive, Steps}
  alias Linkhut.Archiving.Pipeline.{FailureHandler, Helpers, Preflight}

  defp maybe_record_retry(archive, 1), do: archive

  defp maybe_record_retry(archive, attempt) do
    Helpers.update_archive_best_effort(archive, %{
      steps:
        Steps.append_step(archive.steps, "retry", %{
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
  @spec run(Archive.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(%Archive{} = archive, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    archive = maybe_record_retry(archive, attempt)

    all_crawlers = Linkhut.Config.archiving(:crawlers, [])
    {target_crawlers, third_party_crawlers} = partition_by_network_access(all_crawlers)

    run_preflight(archive, target_crawlers)
    |> classify_outcome(third_party_crawlers)
    |> execute_outcome(opts)
  end

  defp classify_outcome({:ok, _meta, archive, eligible}, _tp) when eligible != [] do
    {:dispatch, archive, eligible}
  end

  # preflight_meta is nil when no target_url crawlers are configured
  # (run_preflight skips the HTTP request entirely in that case).
  defp classify_outcome({:ok, preflight_meta, archive, _eligible}, tp) do
    status = if preflight_meta, do: preflight_meta.status

    if is_integer(status) and status >= 400 do
      {:fallback, archive, select_third_party(archive.url, tp), {:http_error, status}}
    else
      {:fail, archive, :no_eligible_crawlers}
    end
  end

  defp classify_outcome({:error, reason, archive}, tp) do
    safe_tp =
      select_third_party(archive.url, tp)
      |> Enum.filter(&FailureHandler.safe_after_failure?(reason, crawler_network_access(&1)))

    {:fallback, archive, safe_tp, reason}
  end

  defp classify_outcome({:fatal, reason, archive}, _tp) do
    {:fail, archive, reason}
  end

  defp execute_outcome({:dispatch, archive, crawlers}, opts) do
    FailureHandler.dispatch_and_finalize(archive, crawlers, opts)
  end

  defp execute_outcome({:fallback, archive, crawlers, reason}, opts) do
    FailureHandler.maybe_dispatch_fallback(archive, crawlers, reason, opts)
  end

  defp execute_outcome({:fail, archive, reason}, opts) do
    FailureHandler.finalize_failure(archive, reason, opts)
  end

  # Runs the preflight pipeline for target_url crawlers.
  # Returns {:ok, preflight_meta, archive, eligible_crawlers},
  #         {:error, reason, archive} for recoverable failures,
  #         {:fatal, reason, archive} for fatal failures.
  defp run_preflight(archive, [] = _target_crawlers) do
    case validate_url(archive) do
      {:ok, archive} -> {:ok, nil, archive, []}
      {:error, reason, archive} -> classify_preflight_error(reason, archive)
    end
  end

  defp run_preflight(archive, target_crawlers) do
    with {:ok, archive} <- validate_url(archive),
         {:ok, preflight_meta, archive} <- Preflight.run(archive),
         {:ok, archive} <- validate_final_url(archive) do
      eligible =
        select_crawlers_from(
          archive.final_url || archive.url,
          preflight_meta,
          target_crawlers
        )

      {:ok, preflight_meta, archive, eligible}
    else
      {:error, reason, archive} -> classify_preflight_error(reason, archive)
    end
  end

  defp classify_preflight_error(reason, archive) do
    if Helpers.fatal?(reason),
      do: {:fatal, reason, archive},
      else: {:error, reason, archive}
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

  defp validate_url(%Archive{url: url} = archive), do: check_host(url, archive)

  defp validate_final_url(%Archive{final_url: nil} = archive), do: {:ok, archive}
  defp validate_final_url(%Archive{final_url: url} = archive), do: check_host(url, archive)

  defp check_host(url, archive) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        case Linkhut.Network.check_address(host) do
          :ok -> {:ok, archive}
          {:error, {:dns_failed, _} = reason} -> {:error, reason, archive}
          {:error, reason} -> {:error, {:reserved_address, reason}, archive}
        end

      _ ->
        {:error, :invalid_url, archive}
    end
  end

  defp select_crawlers_from(url, preflight_meta, crawlers) do
    Enum.filter(crawlers, fn module -> module.can_handle?(url, preflight_meta) end)
  end
end
