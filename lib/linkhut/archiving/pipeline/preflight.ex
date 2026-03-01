defmodule Linkhut.Archiving.Pipeline.Preflight do
  @moduledoc """
  Runs the preflight sub-pipeline: scheme dispatch, metadata
  persistence, and content-length validation.
  """

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, PreflightMeta, Steps}
  alias Linkhut.Archiving.Pipeline.Helpers
  alias Linkhut.Archiving.Preflight, as: PreflightSchemes

  require Logger

  @doc """
  Executes preflight for the given archive's URL.

  Dispatches based on URL scheme — currently supports HTTP/HTTPS.
  Returns `{:ok, %PreflightMeta{}, archive}` on success.
  """
  @spec run(Archive.t()) ::
          {:ok, PreflightMeta.t(), Archive.t()}
          | {:error, term(), Archive.t()}
  def run(%Archive{url: url} = archive) do
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
    case PreflightSchemes.HTTP.execute(url) do
      {:ok, %PreflightMeta{} = meta} ->
        case persist_preflight(archive, meta, url) do
          {:ok, archive} -> check_content_length(meta, archive)
          error -> error
        end

      {:error, reason} ->
        record_preflight_failure(archive, reason)
    end
  end

  defp persist_preflight(archive, %PreflightMeta{} = meta, original_url) do
    detail = build_http_preflight_detail(meta, original_url)

    case Archiving.update_archive(archive, %{
           preflight_meta: meta,
           final_url: meta.final_url,
           steps: Steps.append_step(archive.steps, "preflight", detail)
         }) do
      {:ok, archive} ->
        {:ok, archive}

      {:error, changeset} ->
        Logger.error(
          "Failed to persist preflight metadata for archive #{archive.id}: #{inspect(changeset.errors)}"
        )

        {:error, :preflight_persist_failed, archive}
    end
  end

  defp check_content_length(%PreflightMeta{content_length: cl} = meta, archive) do
    max = Linkhut.Config.archiving(:max_file_size)

    if is_integer(cl) and cl > max do
      {:error, {:file_too_large, cl}, archive}
    else
      {:ok, meta, archive}
    end
  end

  defp record_preflight_failure(archive, reason) do
    archive =
      Helpers.update_archive_best_effort(archive, %{
        steps:
          Steps.append_step(archive.steps, "preflight_failed", %{
            "msg" => "preflight_failed",
            "error" => inspect(reason)
          })
      })

    {:error, :preflight_failed, archive}
  end

  defp build_http_preflight_detail(%PreflightMeta{} = meta, original_url) do
    detail = %{
      "msg" => "preflight_http",
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
