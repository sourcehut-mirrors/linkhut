defmodule LinkhutWeb.Archiving.StepDescriptions do
  @moduledoc """
  Renders machine-readable step detail maps into human-readable,
  localizable strings using gettext.
  """

  use Gettext, backend: LinkhutWeb.Gettext

  @doc """
  Renders a step detail map into a localized string.
  """
  def render(%{"msg" => "created"}), do: gettext("Archive created")

  def render(%{"msg" => "retry", "attempt" => attempt}) do
    gettext("Attempt %{attempt}", attempt: attempt)
  end

  # Scheme-specific preflight messages

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

  def render(%{"msg" => "failed_final"} = detail) do
    gettext("%{error} (attempt %{attempt}/%{max_attempts})",
      error: detail["error"],
      attempt: detail["attempt"],
      max_attempts: detail["max_attempts"]
    )
  end

  # Crawler step messages

  def render(%{"msg" => "crawling"}), do: gettext("Crawling")

  def render(%{"msg" => "crawling_retry", "attempt" => attempt}) do
    gettext("Crawling (attempt %{attempt})", attempt: attempt)
  end

  def render(%{"msg" => "stored", "size" => size}) do
    gettext("Stored %{size}", size: size)
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

  # Fallback
  def render(%{"msg" => msg}), do: msg
  def render(nil), do: nil
end
