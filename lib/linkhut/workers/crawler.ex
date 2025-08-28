defmodule Linkhut.Workers.Crawler do
  @moduledoc """
  Runs a specific crawler (e.g. SingleFile), stores the result via
  `Linkhut.Archiving.Storage`, and creates the snapshot record.
  """

  use Oban.Worker,
    queue: :crawler,
    # Initial attempt + 3 retries
    max_attempts: 4

  alias Linkhut.Archiving

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "link_id" => link_id, "url" => url, "type" => type}} = job) do
    start_time = System.monotonic_time(:millisecond)

    case crawler_module(type) do
      nil ->
        create_failed_snapshot(link_id, job, :unsupported_crawler, start_time)

      module ->
        case apply(module, :fetch, [user_id, link_id, url]) do
          {:ok, result} ->
            processing_time = System.monotonic_time(:millisecond) - start_time
            file_size = get_file_size(result[:path])

            staging_dir = Path.dirname(result[:path])

            case Archiving.Storage.store({:file, result[:path]}, user_id, link_id, type) do
              {:ok, storage_key} ->
                File.rm_rf(staging_dir)

                Archiving.create_snapshot(link_id, job.id, %{
                  type: type,
                  state: :complete,
                  storage_key: storage_key,
                  processing_time_ms: processing_time,
                  file_size_bytes: file_size,
                  response_code: result[:response_code] || 200,
                  crawl_info: result,
                  archive_metadata: %{
                    crawler_version: result[:version],
                    original_url: url,
                    final_url: result[:final_url] || url
                  }
                })

              {:error, storage_error} ->
                File.rm_rf(staging_dir)
                create_failed_snapshot(link_id, job, storage_error, start_time)
            end

          {:error, error} ->
            create_failed_snapshot(link_id, job, error, start_time)
        end
    end
  end

  defp crawler_module("singlefile"), do: Linkhut.Archiving.Crawler.SingleFile
  defp crawler_module(_), do: nil

  defp get_file_size(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp get_file_size(_), do: nil

  defp create_failed_snapshot(link_id, job, error, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    Archiving.create_snapshot(link_id, job.id, %{
      type: job.args["type"],
      state: :failed,
      retry_count: job.attempt - 1,
      failed_at: DateTime.utc_now(),
      processing_time_ms: processing_time,
      archive_metadata: %{error: inspect(error)}
    })
  end
end
