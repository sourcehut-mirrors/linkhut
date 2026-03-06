defmodule Linkhut.Archiving.Preflight.HTTP do
  @moduledoc """
  Executes the HTTP preflight request (HEAD) and returns structured
  metadata. Pure HTTP logic — no DB writes or orchestration.
  """

  alias Linkhut.Archiving.{Crawler, PreflightMeta}

  @doc """
  Sends a HEAD request to `url` and returns parsed preflight metadata.

  Falls back to GET if the server returns 405 (Method Not Allowed).

  On a successful HTTP response (any status), returns `{:ok, %PreflightMeta{}, events}`
  where `events` is a list of step maps recording notable occurrences (e.g. HEAD failure).
  On a transport-level failure, returns `{:error, reason}`.
  """
  @spec execute(String.t()) :: {:ok, PreflightMeta.t(), [{String.t(), map()}]} | {:error, term()}
  def execute(url) do
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
      {:ok, %Req.Response{status: 405}} ->
        execute_get(req_opts)

      {:ok, %Req.Response{} = response} ->
        {:ok, build_meta(response, url, "HEAD"), []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_get(req_opts) do
    req =
      req_opts
      |> Keyword.merge(method: :get, raw: true, into: fn {:data, _}, acc -> {:halt, acc} end)
      |> Req.new()
      |> Req.Request.append_response_steps(capture_url: &capture_final_url/1)

    head_failed_event =
      {"preflight_fallback", %{"msg" => "preflight_head_failed", "status" => 405}}

    case Req.request(req) do
      {:ok, %Req.Response{} = response} ->
        url = Keyword.fetch!(req_opts, :url)
        {:ok, build_meta(response, url, "GET"), [head_failed_event]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_meta(%Req.Response{status: status, headers: headers} = response, url, method) do
    content_type =
      headers
      |> get_header("content-type")
      |> normalize_content_type()

    final_url = get_final_url(response, url)
    content_length = get_content_length(headers)
    scheme = URI.parse(final_url).scheme || URI.parse(url).scheme

    %PreflightMeta{
      scheme: scheme,
      content_type: content_type,
      final_url: final_url,
      status: status,
      content_length: content_length,
      method: method
    }
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
end
