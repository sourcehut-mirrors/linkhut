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

  require Logger

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

        preflight_meta = decode_preflight_meta(args)

        context = %Context{
          user_id: user_id,
          link_id: link_id,
          url: url,
          snapshot_id: snapshot.id,
          preflight_meta: preflight_meta
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
    max_file_size = Linkhut.Config.archiving(:max_file_size)

    if is_integer(file_size) and file_size > max_file_size do
      File.rm_rf(staging_dir)

      update_failed(
        snapshot,
        job,
        %{msg: "file_too_large", size: file_size, max: max_file_size},
        start_time
      )
    else
      case Archiving.Storage.store({:file, result[:path]}, snapshot) do
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
              content_type: result[:content_type],
              original_url: url,
              final_url: result[:final_url] || url
            }
          })

          Archiving.recompute_archive_size_by_id(snapshot.archive_id)
          maybe_mark_old_archives(args)
          Archiving.maybe_complete_archive(snapshot.archive_id)
          :ok

        {:error, storage_error} ->
          File.rm_rf(staging_dir)
          update_failed(snapshot, job, storage_error, start_time)
      end
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

  @known_preflight_keys %{
    "scheme" => :scheme,
    "content_type" => :content_type,
    "content_length" => :content_length,
    "final_url" => :final_url,
    "status" => :status
  }

  defp decode_preflight_meta(%{"preflight_meta" => meta}) when is_map(meta) do
    Map.new(meta, fn {k, v} ->
      {Map.get(@known_preflight_keys, k, k), v}
    end)
  end

  defp decode_preflight_meta(_), do: nil

  # Non-final failures set the snapshot to :retryable (non-terminal), which
  # prevents maybe_complete_archive from marking the archive as :complete
  # while Oban still has retries pending.  Only the final attempt sets :failed
  # (terminal), after which maybe_complete_archive is called.
  defp update_failed(snapshot, job, error, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time
    final_attempt? = job.attempt >= job.max_attempts

    msg =
      if final_attempt?,
        do: "crawler_failed_final",
        else: "crawler_failed_will_retry"

    failed_detail = %{
      "msg" => msg,
      "error" => inspect(error),
      "attempt" => job.attempt,
      "max_attempts" => job.max_attempts
    }

    case Archiving.update_snapshot(snapshot, %{
           state: if(final_attempt?, do: :failed, else: :retryable),
           retry_count: job.attempt - 1,
           failed_at: DateTime.utc_now(),
           processing_time_ms: processing_time,
           crawl_info: Steps.add_crawl_step(snapshot.crawl_info, "failed", failed_detail),
           archive_metadata: %{error: inspect(error)}
         }) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to update snapshot #{snapshot.id} to failed state: #{inspect(changeset.errors)}"
        )
    end

    if final_attempt? do
      Archiving.maybe_complete_archive(snapshot.archive_id)
    end

    {:error, error}
  end
end
