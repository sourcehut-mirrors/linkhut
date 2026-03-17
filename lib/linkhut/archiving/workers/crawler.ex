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
  alias Linkhut.Archiving.PreflightMeta
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
        link_inserted_at = decode_datetime(args["link_inserted_at"])

        context = %Context{
          user_id: user_id,
          link_id: link_id,
          url: url,
          snapshot_id: snapshot.id,
          preflight_meta: preflight_meta,
          link_inserted_at: link_inserted_at
        }

        try do
          case module.fetch(context) do
            {:ok, {:file, result}} ->
              handle_file_result(snapshot, job, result, url, args, start_time)

            {:ok, {:external, result}} ->
              handle_external_result(snapshot, job, result, url, args, start_time)

            {:error, error, :noretry} ->
              update_failed_final(snapshot, job, error, start_time)

            {:error, error} ->
              update_failed(snapshot, job, error, start_time)
          end
        rescue
          exception ->
            Logger.error(
              "Crawler #{inspect(module)} crashed for snapshot #{snapshot.id}: " <>
                Exception.message(exception) <>
                "\n" <> Exception.format_stacktrace(__STACKTRACE__)
            )

            update_failed(snapshot, job, Exception.message(exception), start_time)
        end
    end
  end

  defp handle_file_result(snapshot, job, result, url, args, start_time) do
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
      content_type = result[:content_type] || "application/octet-stream"
      warn_on_missing_content_type(snapshot, result[:content_type])

      case Archiving.Storage.store({:file, result[:path]}, snapshot, content_type: content_type) do
        {:ok, storage_key, store_meta} ->
          File.rm_rf(staging_dir)

          Archiving.update_snapshot(snapshot, %{
            state: :complete,
            storage_key: storage_key,
            processing_time_ms: processing_time,
            file_size_bytes: store_meta.file_size_bytes,
            encoding: store_meta.encoding,
            original_file_size_bytes: if(store_meta.encoding, do: file_size, else: nil),
            response_code: result[:response_code] || 200,
            crawl_info:
              Steps.add_crawl_step(
                snapshot.crawl_info,
                "complete",
                build_stored_msg(store_meta, file_size)
              ),
            archive_metadata: %{
              content_type: result[:content_type],
              original_url: url,
              final_url: result[:final_url] || url
            }
          })

          Archiving.recompute_crawl_run_size_by_id(snapshot.crawl_run_id)
          maybe_mark_old_archives(args)
          Archiving.maybe_complete_crawl_run(snapshot.crawl_run_id)
          :ok

        {:error, storage_error} ->
          File.rm_rf(staging_dir)
          update_failed(snapshot, job, storage_error, start_time)
      end
    end
  end

  defp handle_external_result(snapshot, _job, result, url, args, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time
    storage_key = Linkhut.Archiving.StorageKey.external(result[:url])

    metadata =
      %{
        original_url: url,
        final_url: result[:final_url] || url
      }
      |> Map.merge(Map.drop(result, [:url, :response_code, :final_url]))

    case Archiving.update_snapshot(snapshot, %{
           state: :complete,
           storage_key: storage_key,
           processing_time_ms: processing_time,
           file_size_bytes: nil,
           response_code: result[:response_code],
           crawl_info:
             Steps.add_crawl_step(
               snapshot.crawl_info,
               "complete",
               %{"msg" => "external_snapshot", "url" => result[:url]}
             ),
           archive_metadata: metadata
         }) do
      {:ok, _} ->
        maybe_mark_old_archives(args)
        Archiving.maybe_complete_crawl_run(snapshot.crawl_run_id)
        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to update snapshot #{snapshot.id} with external result: #{inspect(changeset.errors)}"
        )

        {:error, changeset}
    end
  end

  defp warn_on_missing_content_type(snapshot, nil),
    do: Logger.warning("Crawler result for snapshot #{snapshot.id} missing content_type")

  defp warn_on_missing_content_type(_, _), do: :ok

  defp build_stored_msg(store_meta, file_size) do
    base = %{"msg" => "stored", "size" => Linkhut.Formatting.format_bytes(file_size)}

    if store_meta.encoding do
      Map.merge(base, %{
        "compressed_size" => Linkhut.Formatting.format_bytes(store_meta.file_size_bytes),
        "encoding" => store_meta.encoding
      })
    else
      base
    end
  end

  defp maybe_mark_old_archives(args) do
    if Map.get(args, "recrawl", false) do
      link_id = args["link_id"]
      crawl_run_id = Map.get(args, "crawl_run_id")
      Archiving.mark_old_crawl_runs_for_deletion(link_id, exclude: [crawl_run_id])
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

  defp format_error(%{msg: msg}) when is_binary(msg), do: msg
  defp format_error(msg) when is_binary(msg), do: msg
  defp format_error(error), do: inspect(error)

  defp decode_preflight_meta(%{"preflight_meta" => meta}) when is_map(meta),
    do: PreflightMeta.from_map(meta)

  defp decode_preflight_meta(_), do: nil

  defp decode_datetime(iso8601) when is_binary(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp decode_datetime(_), do: nil

  # Non-retryable failure: mark snapshot as :failed immediately and return :ok
  # to tell Oban not to retry. Used when the error is definitive (e.g. "no
  # Wayback Machine snapshot available") and retrying would be pointless.
  defp update_failed_final(snapshot, job, error, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    failed_detail = %{
      "msg" => "crawler_failed_final",
      "error" => format_error(error),
      "attempt" => job.attempt,
      "max_attempts" => job.attempt
    }

    case Archiving.update_snapshot(snapshot, %{
           state: :failed,
           retry_count: job.attempt - 1,
           failed_at: DateTime.utc_now(),
           processing_time_ms: processing_time,
           crawl_info: Steps.add_crawl_step(snapshot.crawl_info, "failed", failed_detail),
           archive_metadata: %{error: format_error(error)}
         }) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to update snapshot #{snapshot.id} to failed state: #{inspect(changeset.errors)}"
        )
    end

    maybe_mark_old_archives(job.args)
    Archiving.maybe_complete_crawl_run(snapshot.crawl_run_id)
    :ok
  end

  # Non-final failures set the snapshot to :retryable (non-terminal), which
  # prevents maybe_complete_crawl_run from marking the crawl run as :complete
  # while Oban still has retries pending.  Only the final attempt sets :failed
  # (terminal), after which maybe_complete_crawl_run is called.
  defp update_failed(snapshot, job, error, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time
    final_attempt? = job.attempt >= job.max_attempts

    msg =
      if final_attempt?,
        do: "crawler_failed_final",
        else: "crawler_failed_will_retry"

    failed_detail = %{
      "msg" => msg,
      "error" => format_error(error),
      "attempt" => job.attempt,
      "max_attempts" => job.max_attempts
    }

    case Archiving.update_snapshot(snapshot, %{
           state: if(final_attempt?, do: :failed, else: :retryable),
           retry_count: job.attempt - 1,
           failed_at: DateTime.utc_now(),
           processing_time_ms: processing_time,
           crawl_info: Steps.add_crawl_step(snapshot.crawl_info, "failed", failed_detail),
           archive_metadata: %{error: format_error(error)}
         }) do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "Failed to update snapshot #{snapshot.id} to failed state: #{inspect(changeset.errors)}"
        )
    end

    if final_attempt? do
      maybe_mark_old_archives(job.args)
      Archiving.maybe_complete_crawl_run(snapshot.crawl_run_id)
    end

    {:error, error}
  end
end
