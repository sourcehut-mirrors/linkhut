defmodule Linkhut.Archiving.Pipeline.Preflight do
  @moduledoc """
  Runs the preflight sub-pipeline: scheme dispatch, metadata
  persistence, and content-length validation.
  """

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{CrawlRun, PreflightMeta, Steps}
  alias Linkhut.Archiving.Pipeline.Helpers
  alias Linkhut.Archiving.Preflight, as: PreflightSchemes

  require Logger

  @doc """
  Executes preflight for the given crawl run's URL.

  Dispatches based on URL scheme — currently supports HTTP/HTTPS.
  Returns `{:ok, %PreflightMeta{}, crawl_run}` on success.
  """
  @spec run(CrawlRun.t()) ::
          {:ok, PreflightMeta.t(), CrawlRun.t()}
          | {:error, term(), CrawlRun.t()}
  def run(%CrawlRun{url: url} = crawl_run) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        http_preflight(crawl_run, url)

      %URI{scheme: scheme} when is_binary(scheme) ->
        {:error, {:unsupported_scheme, scheme}, crawl_run}

      _ ->
        {:error, :invalid_url, crawl_run}
    end
  end

  defp http_preflight(crawl_run, url) do
    case PreflightSchemes.HTTP.execute(url) do
      {:ok, %PreflightMeta{} = meta, events} ->
        case persist_preflight(crawl_run, meta, url, events) do
          {:ok, crawl_run} -> check_content_length(meta, crawl_run)
          error -> error
        end

      {:error, reason} ->
        record_preflight_failure(crawl_run, reason)
    end
  end

  defp persist_preflight(crawl_run, %PreflightMeta{} = meta, original_url, events) do
    detail = build_http_preflight_detail(meta, original_url)

    steps =
      Enum.reduce(events, crawl_run.steps, fn {event_step, event_detail}, acc ->
        Steps.append_step(acc, event_step, event_detail)
      end)

    case Archiving.update_crawl_run(crawl_run, %{
           preflight_meta: meta,
           final_url: meta.final_url,
           steps: Steps.append_step(steps, "preflight", detail)
         }) do
      {:ok, crawl_run} ->
        {:ok, crawl_run}

      {:error, changeset} ->
        Logger.error(
          "Failed to persist preflight metadata for crawl run #{crawl_run.id}: #{inspect(changeset.errors)}"
        )

        {:error, :preflight_persist_failed, crawl_run}
    end
  end

  defp check_content_length(%PreflightMeta{content_length: cl} = meta, crawl_run) do
    max = Linkhut.Config.archiving(:max_file_size)

    if is_integer(cl) and cl > max do
      {:error, {:file_too_large, cl}, crawl_run}
    else
      {:ok, meta, crawl_run}
    end
  end

  defp record_preflight_failure(crawl_run, reason) do
    crawl_run =
      Helpers.update_crawl_run_best_effort(crawl_run, %{
        steps:
          Steps.append_step(crawl_run.steps, "preflight_failed", %{
            "msg" => "preflight_failed",
            "error" => inspect(reason)
          })
      })

    {:error, :preflight_failed, crawl_run}
  end

  defp build_http_preflight_detail(%PreflightMeta{} = meta, original_url) do
    detail = %{
      "msg" => "preflight_http",
      "method" => meta.method,
      "scheme" => meta.scheme,
      "content_type" => meta.content_type,
      "status" => meta.status
    }

    detail =
      if meta.content_length,
        do: Map.put(detail, "size", Linkhut.Formatting.format_bytes(meta.content_length)),
        else: detail

    if meta.final_url != original_url,
      do: Map.put(detail, "final_url", meta.final_url),
      else: detail
  end
end
