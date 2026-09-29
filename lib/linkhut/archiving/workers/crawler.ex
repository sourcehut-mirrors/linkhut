defmodule Linkhut.Archiving.Workers.Crawler do
  @moduledoc "Worker that runs a crawler, stores its result and marks the snapshot as complete"

  use Oban.Worker,
    queue: :crawler,
    # Initial attempt + 3 retries
    max_attempts: 4

  import Ecto.Query, only: [from: 2]

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Log, RateLimit, Snapshot}
  alias Linkhut.Archiving.StorageKey
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  require Logger

  @terminal_states [:complete, :not_available, :failed, :pending_deletion]

  @doc """
  Enqueues the job that runs the crawler for `snapshot` in the crawl run
  `run_id`, on `url`. `opts` are Oban job options.
  """
  @spec enqueue(Snapshot.t(), integer(), String.t(), keyword()) ::
          {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(%Snapshot{} = snapshot, run_id, url, opts) do
    %{"snapshot_id" => snapshot.id, "crawl_run_id" => run_id, "url" => url}
    |> new(opts)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"snapshot_id" => snapshot_id, "crawl_run_id" => run_id}} = job) do
    case Repo.get(Snapshot, snapshot_id) do
      nil ->
        :ok

      %Snapshot{state: state} when state in @terminal_states ->
        :ok

      snapshot ->
        crawl(snapshot, run_id, resolve_crawler(snapshot.source), job)
    end
  end

  defp resolve_crawler(source) do
    Linkhut.Config.archiving(:crawlers, [])
    |> Enum.find(&(&1.source_type() == source))
  end

  defp crawl(snapshot, run_id, nil, job) do
    attempt = %{url: nil, job: job, ms: 0, log: Log.for_snapshot(snapshot, run_id)}
    finish(snapshot, {:error, %{msg: "unsupported_crawler"}, :noretry}, attempt)
  end

  defp crawl(snapshot, run_id, crawler, job) do
    log = Log.for_snapshot(snapshot, run_id)

    with :ok <- check_rate_limit(crawler, log) do
      snapshot = start_attempt(snapshot, log, job.attempt)
      url = job.args["url"]
      staging_dir = staging_dir(snapshot)

      opts = [
        staging_dir: staging_dir,
        format: snapshot.format,
        bookmarked_at: bookmarked_at(snapshot),
        log: log
      ]

      try do
        {micros, result} = :timer.tc(fn -> safe_fetch(crawler, url, opts, snapshot) end)
        finish(snapshot, result, %{url: url, job: job, ms: div(micros, 1000), log: log})
      after
        File.rm_rf(staging_dir)
      end
    end
  end

  defp start_attempt(snapshot, log, attempt) do
    {:ok, snapshot} = Archiving.update_snapshot(snapshot, %{state: :crawling})
    Log.append(log, "crawler.started", %{attempt: attempt})
    snapshot
  end

  defp check_rate_limit(crawler, log) do
    with true <- function_exported?(crawler, :rate_limit, 0),
         {scale_ms, limit} = crawler.rate_limit(),
         {:deny, _limit} <- RateLimit.hit("crawler:#{crawler.source_type()}", scale_ms, limit) do
      jitter = :rand.uniform(max(div(scale_ms, 4000), 1))
      seconds = max(div(scale_ms, 1000) + jitter, 1)

      Log.append(log, "crawler.rate_limited", %{snooze_seconds: seconds})

      {:snooze, seconds}
    else
      _ -> :ok
    end
  end

  defp staging_dir(snapshot) do
    dir =
      Linkhut.Config.archiving(:staging_dir, System.tmp_dir!())
      |> Path.join("snapshot-#{snapshot.id}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp bookmarked_at(snapshot) do
    Repo.one(from l in Link, where: l.id == ^snapshot.link_id, select: l.inserted_at)
  end

  defp safe_fetch(crawler, url, opts, snapshot) do
    crawler.fetch(url, opts)
  rescue
    exception ->
      Logger.error(
        "Crawler #{inspect(crawler)} crashed for snapshot #{snapshot.id}: " <>
          Exception.message(exception) <>
          "\n" <> Exception.format_stacktrace(__STACKTRACE__)
      )

      {:error, Exception.message(exception)}
  end

  defp finish(snapshot, {:ok, {:file, file}}, attempt) do
    case store(snapshot, file, attempt.url) do
      {:ok, attrs, data} -> mark(snapshot, :complete, attrs, {"crawler.stored", data}, attempt)
      error -> finish(snapshot, error, attempt)
    end
  end

  defp finish(snapshot, {:ok, {:external, result}}, attempt) do
    attrs = %{
      storage_key: StorageKey.external(result[:url]),
      response_code: result[:response_code],
      archive_metadata:
        Map.merge(
          %{original_url: attempt.url, final_url: result[:final_url] || attempt.url},
          Map.drop(result, [:url, :response_code, :final_url])
        )
    }

    mark(snapshot, :complete, attrs, {"crawler.linked", %{url: result[:url]}}, attempt)
  end

  defp finish(snapshot, {:ok, :not_available}, attempt) do
    mark(snapshot, :not_available, %{}, {"crawler.not_available", %{}}, attempt)
  end

  defp finish(snapshot, {:error, error, :noretry}, attempt) do
    {:cancel, fail(snapshot, error, attempt)}
  end

  defp finish(_snapshot, {:error, error}, %{job: %{attempt: n, max_attempts: max}} = attempt)
       when n < max do
    {message, _code} = error_info(error)

    Log.append(
      attempt.log,
      "crawler.attempt_failed",
      %{error: message, attempt: n, max_attempts: max},
      level: :warning
    )

    {:error, error}
  end

  defp finish(snapshot, {:error, error}, attempt) do
    fail(snapshot, error, attempt)
    {:error, error}
  end

  defp store(snapshot, file, url) do
    if is_nil(file[:content_type]),
      do: Logger.warning("Crawler result for snapshot #{snapshot.id} missing content_type")

    content_type = file[:content_type] || "application/octet-stream"

    case Archiving.store_file(snapshot, file[:path], content_type) do
      {:ok, stored} ->
        {:ok, stored_attrs(stored, file, url), stored_data(stored)}

      {:error, {:file_too_large, size, max}} ->
        {:error, %{msg: "file_too_large", size: size, max: max}, :noretry}

      error ->
        error
    end
  end

  defp stored_attrs(stored, file, url) do
    Map.merge(stored, %{
      response_code: file[:response_code] || 200,
      archive_metadata: %{
        content_type: file[:content_type],
        original_url: url,
        final_url: file[:final_url] || url
      }
    })
  end

  defp stored_data(stored) do
    %{
      size_bytes: stored.original_file_size_bytes || stored.file_size_bytes,
      stored_bytes: if(stored.encoding, do: stored.file_size_bytes),
      encoding: stored.encoding
    }
  end

  defp mark(snapshot, state, attrs, {event, data}, attempt, log_opts \\ []) do
    attrs = Map.put(attrs, :processing_time_ms, attempt.ms)

    with {:ok, _snapshot} <- Archiving.mark_snapshot(snapshot, state, attrs) do
      Log.append(attempt.log, event, data, log_opts)
    end
  end

  defp fail(snapshot, error, %{job: job} = attempt) do
    {message, code} = error_info(error)

    attrs = %{
      retry_count: job.attempt - 1,
      failed_at: DateTime.utc_now(),
      archive_metadata: %{error: message, error_code: code}
    }

    data = %{error: message, attempt: job.attempt, max_attempts: job.max_attempts}
    mark(snapshot, :failed, attrs, {"crawler.failed", data}, attempt, level: :error)
    message
  end

  defp error_info(%{msg: msg}) when is_binary(msg), do: {msg, msg}
  defp error_info(msg) when is_binary(msg), do: {msg, "crawler_error"}
  defp error_info(error), do: {inspect(error), "crawler_error"}
end
