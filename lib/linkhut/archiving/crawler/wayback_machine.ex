defmodule Linkhut.Archiving.Crawler.WaybackMachine do
  @moduledoc """
  Crawler that queries the Internet Archive's Wayback Machine CDX API
  for existing snapshots of a bookmarked URL, closest to when the user
  saved their bookmark.

  Unlike file-based crawlers, this produces an external reference (a
  Wayback Machine URL) rather than a downloaded file.
  """

  @behaviour Linkhut.Archiving.Crawler

  alias Linkhut.Archiving.Crawler.Context

  require Logger

  @cdx_url "https://web.archive.org/cdx/search/cdx"

  @impl true
  def type, do: "wayback"

  @impl true
  def meta, do: %{tool_name: "Wayback CDX API", version: nil}

  @impl true
  def network_access, do: :third_party

  @impl true
  def queue, do: :crawler

  @impl true
  def rate_limit, do: {60_000, 40}

  @impl true
  def can_handle?(url, _preflight_meta) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        not localhost?(host)

      _ ->
        false
    end
  end

  @impl true
  def fetch(%Context{url: url, link_inserted_at: link_inserted_at}) do
    timestamp = format_timestamp(link_inserted_at || DateTime.utc_now())

    case query_cdx(url, timestamp) do
      {:ok, capture} ->
        wayback_url = "https://web.archive.org/web/#{capture.timestamp}/#{capture.original}"

        {:ok,
         {:external,
          %{
            url: wayback_url,
            timestamp: capture.timestamp,
            response_code: capture.status_code
          }}}

      :not_available ->
        {:ok, :not_available}

      {:error, reason, :noretry} ->
        {:error, %{msg: reason}, :noretry}

      {:error, reason} ->
        {:error, %{msg: reason}}
    end
  end

  defp query_cdx(url, timestamp) do
    req_opts =
      [
        url: @cdx_url,
        method: :get,
        params: [
          url: strip_scheme(url),
          output: "json",
          fl: "timestamp,original,statuscode",
          filter: "statuscode:200",
          closest: timestamp,
          sort: "closest",
          limit: 1
        ],
        retry: false,
        receive_timeout: 30_000
      ]
      |> Keyword.merge(Application.get_env(:linkhut, :wayback_req_options, []))

    case Req.request(Req.new(req_opts)) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_cdx_response(body)

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, "Wayback API error: HTTP #{status}"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "Wayback API rate limited"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Wayback API error: HTTP #{status}", :noretry}

      {:error, reason} ->
        {:error, "Wayback API error: #{inspect(reason)}"}
    end
  end

  defp parse_cdx_response([_header, [timestamp, original, statuscode] | _]) do
    {:ok,
     %{
       timestamp: timestamp,
       original: original,
       status_code: parse_status(statuscode)
     }}
  end

  defp parse_cdx_response([_header]) do
    :not_available
  end

  defp parse_cdx_response([]) do
    :not_available
  end

  defp parse_cdx_response(body) when is_binary(body) do
    body = String.trim(body)

    if body == "" do
      :not_available
    else
      {:error, "Wayback API returned invalid response"}
    end
  end

  defp parse_cdx_response(_), do: {:error, "Wayback API returned invalid response"}

  defp strip_scheme(url), do: String.replace(url, ~r{^https?://}, "")

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y%m%d%H%M%S")
  end

  defp parse_status(status) when is_binary(status) do
    case Integer.parse(status) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_status(status) when is_integer(status), do: status
  defp parse_status(_), do: nil

  defp localhost?(host) do
    host in ["localhost", "127.0.0.1", "::1", "[::1]"] or
      String.ends_with?(host, ".localhost")
  end
end
