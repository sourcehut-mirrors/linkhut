defmodule Linkhut.Workers.Archiver do
  @moduledoc """
  Validates a link's URL (SSRF checks, redirect following) and dispatches
  per-crawler jobs via `Linkhut.Workers.Crawler`.
  """

  use Oban.Worker,
    queue: :default,
    # Initial attempt + 3 retries
    max_attempts: 4

  alias Linkhut.Archiving

  def enqueue(link, opts \\ []) do
    %{user_id: link.user_id, link_id: link.id, url: link.url}
    |> Linkhut.Workers.Archiver.new(opts)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "link_id" => link_id, "url" => link_url}} = job) do
    start_time = System.monotonic_time(:millisecond)

    case validate_url(link_url) do
      {:ok, final_url} ->
        result = dispatch_crawlers(user_id, link_id, final_url)
        {:ok, result}

      {:error, reason} ->
        if job.attempt >= job.max_attempts do
          create_failed_snapshot(link_id, job, reason, start_time)
        end

        {:error, reason}
    end
  end

  defp validate_url(url) do
    with {:ok, %URI{host: host}} <- parse_url(url),
         false <- Linkhut.Network.local_address?(host),
         {:ok, final_url} <- follow_redirects(url),
         {:ok, %URI{host: final_host}} <- parse_url(final_url),
         false <- Linkhut.Network.local_address?(final_host) do
      {:ok, final_url}
    else
      true -> {:error, :local_address}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_url}
    end
  end

  defp parse_url(url),
    do: URI.parse(url) |> then(&if &1.host, do: {:ok, &1}, else: {:error, :no_host})

  defp follow_redirects(url) do
    # dummy implementation assuming no redirect for now
    {:ok, url}
  end

  defp dispatch_crawlers(user_id, link_id, url) do
    {:ok, %URI{scheme: scheme}} = parse_url(url)

    crawlers =
      case scheme do
        "http" -> [:singlefile]
        "https" -> [:singlefile]
        _ -> []
      end

    crawl_jobs =
      Enum.map(crawlers, fn crawler ->
        job =
          Linkhut.Workers.Crawler.new(%{"user_id" => user_id, "link_id" => link_id, "url" => url, "type" => to_string(crawler)})

        {:ok, job} = Oban.insert(job)
        %{name: crawler, job_id: job.id}
      end)

    %{timestamp: DateTime.utc_now(), crawlers: crawl_jobs}
  end

  defp create_failed_snapshot(link_id, job, reason, start_time) do
    processing_time = System.monotonic_time(:millisecond) - start_time

    Archiving.create_snapshot(link_id, job.id, %{
      type: "error",
      state: :failed,
      retry_count: job.attempt - 1,
      failed_at: DateTime.utc_now(),
      processing_time_ms: processing_time,
      archive_metadata: %{error: inspect(reason)}
    })
  end
end
