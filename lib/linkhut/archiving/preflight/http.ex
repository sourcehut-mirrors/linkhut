defmodule Linkhut.Archiving.Preflight.HTTP do
  @moduledoc """
  Executes the HTTP preflight request (HEAD) and returns structured
  metadata.
  """

  alias Linkhut.Archiving.{Crawler, Log, MIME, PreflightMeta}

  @max_redirects 5

  @doc """
  Sends a HEAD request to `url` (falls back to using GET), and checks the final
  URL with `check_url/1`.
  """
  @spec execute(String.t(), keyword()) ::
          {:ok, PreflightMeta.t()} | {:unusable, Crawler.reject_reason()} | {:unreachable, term()}
  def execute(url, opts \\ []) do
    log = Keyword.get(opts, :log)

    case request(url, :head, log) do
      {:ok, meta} = ok ->
        Log.append(log, "preflight.completed", meta |> Map.from_struct() |> Map.put(:url, url))
        ok

      {:unusable, reason} = unusable ->
        Log.append(log, "preflight.blocked", Map.put(reason, :url, url), level: :warning)
        unusable

      {:unreachable, reason} = unreachable ->
        data = %{url: url, error: inspect(reason)}
        Log.append(log, "preflight.failed", data, level: :warning)
        unreachable
    end
  end

  @doc """
  Checks that `url` is http or https and that it resolves to a public
  address.
  """
  @spec check_url(String.t()) ::
          :ok | {:unusable, Crawler.reject_reason()} | {:unreachable, term()}
  def check_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        check_address(host)

      %URI{scheme: scheme} when is_binary(scheme) and scheme not in ["http", "https"] ->
        {:unusable, %{reason: :unsupported_scheme, scheme: scheme}}

      _ ->
        {:unusable, %{reason: :invalid_url}}
    end
  end

  defp check_address(host) do
    case Linkhut.Network.check_address(host) do
      :ok ->
        :ok

      {:error, {:dns_failed, _host} = reason} ->
        {:unreachable, reason}

      {:error, {:reserved, range, host}} ->
        {:unusable, %{reason: :reserved_address, host: host, range: range}}
    end
  end

  defp request(url, method, log) do
    case url |> req(method) |> Req.run() do
      {_request, %Req.Response{status: 405}} when method == :head ->
        Log.append(log, "preflight.head_rejected", %{url: url, status: 405})
        request(url, :get, log)

      {request, %Req.Response{} = response} ->
        final_url = URI.to_string(request.url)

        case check_url(final_url) do
          :ok -> {:ok, build_meta(response, final_url, method)}
          {:unusable, reason} -> {:unusable, Map.put(reason, :redirect, final_url)}
          {:unreachable, _reason} = unreachable -> unreachable
        end

      {_request, exception} ->
        {:unreachable, exception}
    end
  end

  defp req(url, method) do
    [
      url: url,
      method: method,
      max_redirects: @max_redirects,
      retry: false,
      headers: [user_agent: Crawler.user_agent()]
    ]
    |> Keyword.merge(Application.get_env(:linkhut, :req_options, []))
    |> Keyword.merge(body_options(method))
    |> Req.new()
  end

  defp body_options(:get), do: [raw: true, into: fn {:data, _}, acc -> {:halt, acc} end]
  defp body_options(:head), do: []

  defp build_meta(%Req.Response{status: status, headers: headers}, url, method) do
    %PreflightMeta{
      scheme: URI.parse(url).scheme,
      content_type: headers |> get_header("content-type") |> MIME.media_type(),
      final_url: url,
      status: status,
      content_length: get_content_length(headers),
      method: method |> Atom.to_string() |> String.upcase()
    }
  end

  defp get_header(headers, key) do
    case headers do
      %{^key => [value | _]} -> value
      _ -> nil
    end
  end

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
