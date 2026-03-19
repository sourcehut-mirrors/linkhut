defmodule LinkhutWeb.Archiving.StepDescriptions do
  @moduledoc """
  Renders machine-readable step detail maps into human-readable,
  localizable strings using gettext.
  """

  use Gettext, backend: LinkhutWeb.Gettext

  @doc """
  Renders a step detail map into a localized string.
  """
  def render(%{"msg" => "created"}), do: gettext("Archival task initiated")

  def render(%{"msg" => "reconciliation", "new_types" => types})
      when is_list(types) do
    gettext("Reconciliation (%{crawlers})", crawlers: Enum.join(types, ", "))
  end

  def render(%{"msg" => "retry", "attempt" => attempt}) do
    gettext("Attempt %{attempt}", attempt: attempt)
  end

  # Scheme-specific preflight messages

  def render(%{"msg" => "preflight_head_failed", "status" => status}) do
    gettext("HEAD returned %{status}, retrying with GET", status: status)
  end

  def render(%{"msg" => "preflight_http"} = detail) do
    parts =
      [detail["content_type"], to_string(detail["status"])]
      |> Enum.reject(&is_nil/1)

    parts =
      if detail["size"],
        do: parts ++ [detail["size"]],
        else: parts

    parts =
      if detail["final_url"],
        do: parts ++ ["→ #{detail["final_url"]}"],
        else: parts

    Enum.join(parts, "; ")
  end

  def render(%{"msg" => "validation_failed", "error" => error}) do
    gettext("Validation failed: %{error}", error: error)
  end

  def render(%{"msg" => "preflight_failed", "error" => error}) do
    gettext("Preflight failed: %{error}", error: error)
  end

  def render(%{"msg" => "dispatched", "crawlers" => crawlers}) do
    gettext("Dispatched to %{crawlers}", crawlers: crawlers)
  end

  def render(%{"msg" => "failed_will_retry"} = detail) do
    gettext("%{error} (attempt %{attempt}/%{max_attempts}, will retry)",
      error: detail["error"],
      attempt: detail["attempt"],
      max_attempts: detail["max_attempts"]
    )
  end

  def render(
        %{"msg" => "failed_final", "attempt" => attempt, "max_attempts" => max_attempts} = detail
      ) do
    gettext("%{error} (attempt %{attempt}/%{max_attempts})",
      error: detail["error"],
      attempt: attempt,
      max_attempts: max_attempts
    )
  end

  def render(%{"msg" => "failed_final", "error" => error}) do
    gettext("Non-retryable failure: %{error}", error: error)
  end

  # Crawler step messages

  def render(%{"msg" => "rate_limited", "crawler" => crawler}) do
    gettext("Rate limited, retrying (%{crawler})", crawler: crawler)
  end

  def render(%{"msg" => "crawling"}), do: gettext("Crawling")

  def render(%{"msg" => "crawling_retry", "attempt" => attempt}) do
    gettext("Crawling (attempt %{attempt})", attempt: attempt)
  end

  def render(%{"msg" => "stored", "size" => size}) do
    gettext("Stored %{size}", size: size)
  end

  def render(%{"msg" => "external_snapshot", "url" => url}) do
    gettext("External snapshot: %{url}", url: url)
  end

  def render(%{"msg" => "not_available"}), do: gettext("Not available from this source")

  def render(%{"msg" => "not_archivable", "reason" => "invalid_url"}) do
    gettext("Not archivable: invalid URL")
  end

  def render(%{"msg" => "not_archivable", "reason" => "unsupported_scheme:" <> scheme}) do
    gettext("Not archivable: unsupported scheme (%{scheme})", scheme: scheme)
  end

  def render(%{"msg" => "not_archivable", "reason" => "reserved_address"}) do
    gettext("Not archivable: private or reserved address")
  end

  def render(%{"msg" => "not_archivable", "reason" => "no_eligible_crawlers"}) do
    gettext("Not archivable: unsupported content")
  end

  def render(%{"msg" => "not_archivable", "reason" => "file_too_large"}) do
    gettext("Not archivable: file too large")
  end

  def render(%{"msg" => "not_archivable"}) do
    gettext("Not archivable")
  end

  def render(%{"msg" => "partial_failure", "error" => error}) do
    gettext("Partial failure: %{error}", error: error)
  end

  def render(%{"msg" => "crawler_failed_will_retry"} = detail) do
    gettext("%{error} (attempt %{attempt}/%{max_attempts}, will retry)",
      error: detail["error"],
      attempt: detail["attempt"],
      max_attempts: detail["max_attempts"]
    )
  end

  def render(%{"msg" => "crawler_failed_final"} = detail) do
    gettext("%{error} (attempt %{attempt}/%{max_attempts})",
      error: detail["error"],
      attempt: detail["attempt"],
      max_attempts: detail["max_attempts"]
    )
  end

  def render(%{"msg" => "completed"}), do: gettext("Archival task completed")

  # Fallback
  def render(%{"msg" => msg}), do: msg
  def render(nil), do: nil
end
