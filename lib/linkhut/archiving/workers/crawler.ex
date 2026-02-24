defmodule Linkhut.Archiving.Workers.Crawler do
  @moduledoc """
  Runs a specific crawler (e.g. SingleFile), stores the result via
  `Linkhut.Archiving.Storage`, and updates the existing snapshot record.
  """

  use Oban.Worker,
    queue: :crawler,
    # Initial attempt + 3 retries
    max_attempts: 4

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Crawler.Context
  alias Linkhut.Archiving.Steps

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    %{
      "snapshot_id" => snapshot_id,
      "user_id" => user_id,
      "link_id" => link_id,
      "url" => url,
      "type" => type
    } = args

    start_time = System.monotonic_time(:millisecond)

    case Archiving.get_snapshot_by_id(snapshot_id) do
      nil -> :ok
      %{state: state} when state in [:complete, :pending_deletion] -> :ok
      snapshot -> run_crawler(snapshot, job, type, user_id, link_id, url, args, start_time)
    end
  end

  defp run_crawler(snapshot, job, type, user_id, link_id, url, args, start_time) do
    case resolve_crawler(type) do
      nil ->
        update_failed(snapshot, job, :unsupported_crawler, start_time)

      module ->
        crawl_detail =
          if job.attempt > 1,
            do: %{"msg" => "crawling_retry", "attempt" => job.attempt},
            else: %{"msg" => "crawling"}

        {:ok, snapshot} =
          Archiving.update_snapshot(snapshot, %{
            state: :crawling,
            crawl_info: Steps.add_crawl_step(snapshot.crawl_info, "crawling", crawl_detail)
          })

        context = %Context{
          user_id: user_id,
          link_id: link_id,
          url: url,
          snapshot_id: snapshot.id
        }

        case module.fetch(context) do
          {:ok, result} ->
            handle_crawl_success(snapshot, job, result, url, args, start_time)

          {:error, error} ->
            update_failed(snapshot, job, error, start_time)
        end
    end
  end

  defp handle_crawl_success(snapshot, job, result, url, args, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time
    file_size = get_file_size(result[:path])
    staging_dir = Path.dirname(result[:path])
    type = job.args["type"]

    case Archiving.Storage.store({:file, result[:path]}, snapshot.user_id, snapshot.link_id, type) do
      {:ok, storage_key} ->
        File.rm_rf(staging_dir)

        Archiving.update_snapshot(snapshot, %{
          state: :complete,
          storage_key: storage_key,
          processing_time_ms: processing_time,
          file_size_bytes: file_size,
          response_code: result[:response_code] || 200,
          crawl_info:
            Steps.add_crawl_step(
              snapshot.crawl_info,
              "complete",
              %{"msg" => "stored", "size" => Linkhut.Formatting.format_bytes(file_size)}
            ),
          archive_metadata: %{
            crawler_version: result[:version],
            original_url: url,
            final_url: result[:final_url] || url
          }
        })

        maybe_mark_old_archives(args)
        :ok

      {:error, storage_error} ->
        File.rm_rf(staging_dir)
        update_failed(snapshot, job, storage_error, start_time)
    end
  end

  defp maybe_mark_old_archives(args) do
    if Map.get(args, "recrawl", false) do
      link_id = args["link_id"]
      archive_id = Map.get(args, "archive_id")
      Archiving.mark_old_archives_for_deletion(link_id, exclude: [archive_id])
    end
  end

  defp resolve_crawler(type) do
    Linkhut.Config.archiving(:crawlers, [])
    |> Enum.find(fn module -> module.type() == type end)
  end

  defp get_file_size(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp get_file_size(_), do: nil

  defp update_failed(snapshot, job, error, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    msg =
      if job.attempt < job.max_attempts,
        do: "crawler_failed_will_retry",
        else: "crawler_failed_final"

    failed_detail = %{
      "msg" => msg,
      "error" => inspect(error),
      "attempt" => job.attempt,
      "max_attempts" => job.max_attempts
    }

    Archiving.update_snapshot(snapshot, %{
      state: :failed,
      retry_count: job.attempt - 1,
      failed_at: DateTime.utc_now(),
      processing_time_ms: processing_time,
      crawl_info: Steps.add_crawl_step(snapshot.crawl_info, "failed", failed_detail),
      archive_metadata: %{error: inspect(error)}
    })

    {:error, error}
  end
end
