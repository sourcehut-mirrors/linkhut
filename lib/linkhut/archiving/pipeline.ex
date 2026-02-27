defmodule Linkhut.Archiving.Pipeline do
  @moduledoc """
  Orchestrates the archiving pipeline: URL validation, HEAD request,
  crawler selection, and atomic dispatch. Extracted from the Archiver
  worker for unit-testability without Oban.
  """

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Crawler, Steps}
  alias Linkhut.Repo
  alias Linkhut.Archiving.Workers.Crawler, as: CrawlerWorker

  require Logger

  @doc """
  Runs the full archiving pipeline for the given archive.

  1. Validates URL (SSRF check)
  2. Preflight request to get content_type, final_url, status
  3. SSRF check on final_url
  4. Updates archive with preflight_meta
  5. Selects eligible crawlers via can_handle?/2
  6. Atomically dispatches crawler jobs + creates pending snapshots

  Options:
    - `:recrawl` - boolean, whether this is a re-crawl attempt
  """
  def run(%Archive{} = archive, opts \\ []) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    archive =
      if attempt > 1 do
        case Archiving.update_archive(archive, %{
               steps:
                 Steps.append_step(archive.steps, "retry", %{
                   "msg" => "retry",
                   "attempt" => attempt
                 })
             }) do
          {:ok, archive} ->
            archive

          {:error, changeset} ->
            Logger.warning(
              "Failed to record retry step for archive #{archive.id}: #{inspect(changeset.errors)}"
            )

            archive
        end
      else
        archive
      end

    with {:ok, archive} <- validate_url(archive),
         {:ok, preflight_meta, archive} <- preflight(archive),
         {:ok, archive} <- validate_final_url(archive),
         crawlers <- select_crawlers(archive.final_url || archive.url, preflight_meta),
         {:ok, result} <- dispatch_crawlers(archive, crawlers, opts) do
      {:ok, result}
    else
      {:error, reason, archive} ->
        final_attempt? = attempt >= max_attempts

        msg = if final_attempt?, do: "failed_final", else: "failed_will_retry"

        failed_detail = %{
          "msg" => msg,
          "error" => inspect(reason),
          "attempt" => attempt,
          "max_attempts" => max_attempts
        }

        state_update =
          if final_attempt?,
            do: %{state: :failed, error: inspect(reason)},
            else: %{error: inspect(reason)}

        Archiving.update_archive(
          archive,
          Map.put(state_update, :steps, Steps.append_step(archive.steps, "failed", failed_detail))
        )

        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_url(%Archive{url: url} = archive) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        case Linkhut.Network.check_address(host) do
          :ok -> {:ok, archive}
          {:error, reason} -> {:error, {:reserved_address, reason}, archive}
        end

      _ ->
        {:error, :invalid_url, archive}
    end
  end

  @doc """
  Performs a preflight request to get content type, final URL, and status.
  Dispatches based on URL scheme — currently supports HTTP/HTTPS.
  """
  def preflight(%Archive{url: url} = archive) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        http_preflight(archive, url)

      %URI{scheme: scheme} when is_binary(scheme) ->
        {:error, {:unsupported_scheme, scheme}, archive}

      _ ->
        {:error, :invalid_url, archive}
    end
  end

  defp http_preflight(archive, url) do
    req_opts =
      [
        url: url,
        method: :head,
        redirect: true,
        max_redirects: 5,
        headers: [user_agent: Crawler.user_agent()]
      ]
      |> Keyword.merge(Application.get_env(:linkhut, :req_options, []))

    req =
      Req.new(req_opts)
      |> Req.Request.append_response_steps(capture_url: &capture_final_url/1)

    case Req.request(req) do
      {:ok, %Req.Response{status: status, headers: headers} = response} ->
        content_type =
          headers
          |> get_header("content-type")
          |> normalize_content_type()

        final_url = get_final_url(response, url)
        content_length = get_content_length(headers)
        scheme = URI.parse(final_url).scheme || URI.parse(url).scheme

        preflight_meta = %{
          scheme: scheme,
          content_type: content_type,
          final_url: final_url,
          status: status,
          content_length: content_length
        }

        preflight_detail =
          build_http_preflight_detail(
            scheme,
            content_type,
            status,
            content_length,
            final_url,
            url
          )

        case Archiving.update_archive(archive, %{
               preflight_meta: preflight_meta,
               final_url: final_url,
               steps: Steps.append_step(archive.steps, "preflight", preflight_detail)
             }) do
          {:ok, archive} ->
            max_file_size = Linkhut.Config.archiving(:max_file_size)

            if is_integer(content_length) and content_length > max_file_size do
              {:error, {:file_too_large, content_length}, archive}
            else
              {:ok, preflight_meta, archive}
            end

          {:error, changeset} ->
            Logger.error(
              "Failed to persist preflight metadata for archive #{archive.id}: #{inspect(changeset.errors)}"
            )

            {:error, :preflight_persist_failed, archive}
        end

      {:error, reason} ->
        archive =
          case Archiving.update_archive(archive, %{
                 steps:
                   Steps.append_step(archive.steps, "preflight_failed", %{
                     "msg" => "preflight_failed",
                     "error" => inspect(reason)
                   })
               }) do
            {:ok, archive} ->
              archive

            {:error, changeset} ->
              Logger.warning(
                "Failed to record preflight_failed step for archive #{archive.id}: #{inspect(changeset.errors)}"
              )

              archive
          end

        {:error, :preflight_failed, archive}
    end
  end

  defp validate_final_url(%Archive{final_url: nil} = archive), do: {:ok, archive}

  defp validate_final_url(%Archive{final_url: final_url} = archive) do
    case URI.parse(final_url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        case Linkhut.Network.check_address(host) do
          :ok -> {:ok, archive}
          {:error, reason} -> {:error, {:reserved_address, reason}, archive}
        end

      _ ->
        {:error, :invalid_url, archive}
    end
  end

  @doc """
  Selects eligible crawlers from configured list via `can_handle?/2`.
  """
  def select_crawlers(url, preflight_meta) do
    Linkhut.Config.archiving(:crawlers, [])
    |> Enum.filter(fn module -> module.can_handle?(url, preflight_meta) end)
  end

  @doc """
  Atomically creates pending snapshots and enqueues Crawler jobs.
  Uses Repo.transaction + Oban.insert_all for atomicity.
  """
  def dispatch_crawlers(archive, [], _opts) do
    {:error, :no_eligible_crawlers, archive}
  end

  def dispatch_crawlers(%Archive{} = archive, crawlers, opts) when is_list(crawlers) do
    indexed_crawlers = Enum.with_index(crawlers)
    preflight_meta = archive.preflight_meta

    multi =
      Enum.reduce(indexed_crawlers, Ecto.Multi.new(), fn {crawler_module, idx}, multi ->
        type = crawler_module.type()

        multi
        |> Ecto.Multi.run({:snapshot, idx}, fn _repo, _changes ->
          Archiving.create_snapshot(archive.link_id, archive.user_id, %{
            archive_id: archive.id,
            type: type,
            state: :pending,
            crawler_meta: crawler_module.meta()
          })
        end)
        |> Oban.insert({:job, idx}, fn changes ->
          snapshot = changes[{:snapshot, idx}]

          CrawlerWorker.new(%{
            "snapshot_id" => snapshot.id,
            "user_id" => archive.user_id,
            "link_id" => archive.link_id,
            "url" => archive.final_url || archive.url,
            "type" => type,
            "recrawl" => Keyword.get(opts, :recrawl, false),
            "archive_id" => archive.id,
            "preflight_meta" => encode_preflight_meta(preflight_meta)
          })
        end)
        |> Ecto.Multi.run({:link_snapshot_job, idx}, fn _repo, changes ->
          snapshot = changes[{:snapshot, idx}]
          job = changes[{:job, idx}]
          Archiving.update_snapshot(snapshot, %{job_id: job.id})
        end)
      end)
      |> Ecto.Multi.run(:update_archive, fn _repo, _changes ->
        crawler_names = Enum.map_join(crawlers, ", ", & &1.type())

        Archiving.update_archive(archive, %{
          steps:
            Steps.append_step(archive.steps, "dispatched", %{
              "msg" => "dispatched",
              "crawlers" => crawler_names
            })
        })
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        {:ok,
         %{
           timestamp: DateTime.utc_now(),
           crawlers:
             Enum.map(indexed_crawlers, fn {mod, idx} ->
               job = changes[{:job, idx}]
               %{name: mod.type(), job_id: job.id}
             end)
         }}

      {:error, _step, reason, _changes} ->
        {:error, reason, archive}
    end
  end

  defp build_http_preflight_detail(
         scheme,
         content_type,
         status,
         content_length,
         final_url,
         original_url
       ) do
    detail = %{
      "msg" => "preflight_http",
      "scheme" => scheme,
      "content_type" => content_type,
      "status" => status
    }

    detail =
      if content_length,
        do: Map.put(detail, "size", Linkhut.Formatting.format_bytes(content_length)),
        else: detail

    if final_url != original_url,
      do: Map.put(detail, "final_url", final_url),
      else: detail
  end

  defp get_header(headers, key) do
    case headers do
      %{^key => [value | _]} -> value
      _ -> nil
    end
  end

  defp normalize_content_type(nil), do: nil

  defp normalize_content_type(content_type) do
    content_type
    |> String.split(";")
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp capture_final_url({request, response}) do
    final_url = URI.to_string(request.url)
    {request, Req.Response.put_private(response, :final_url, final_url)}
  end

  defp get_final_url(%Req.Response{private: %{final_url: url}}, _original_url), do: url
  defp get_final_url(_response, original_url), do: original_url

  defp get_content_length(headers) do
    case get_header(headers, "content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {n, _} -> n
          :error -> nil
        end
    end
  end

  defp encode_preflight_meta(nil), do: nil

  defp encode_preflight_meta(meta) when is_map(meta) do
    Map.new(meta, fn {k, v} -> {to_string(k), v} end)
  end
end
