defmodule Linkhut.Links.Url do
  @moduledoc """
  URL transformation utilities for bookmarks.
  """

  # Schemes known to use DNS hostnames (case-insensitive per RFC 1034 §3.1).
  @dns_schemes ~w(http https ftp gemini gopher)

  # Canonical list of tracking parameters, organized by source for self-documentation.
  @tracking_params_by_source [
    {"UTM", ~w[utm_source utm_medium utm_campaign utm_term utm_content utm_id]},
    {"Google Ads", ~w[gclid gclsrc dclid gbraid wbraid _ga _gl]},
    {"Meta (Facebook/Instagram)", ~w[fbclid igshid]},
    {"Microsoft Ads", ~w[msclkid]},
    {"eX-Twitter", ~w[twclid]},
    {"TikTok", ~w[ttclid]},
    {"Mailchimp", ~w[mc_cid mc_eid]},
    {"HubSpot", ~w[_hsenc _hsmi __hstc __hsfp hsCtaTracking]},
    {"Klaviyo", ~w[_kx]},
    {"Marketo", ~w[mkt_tok]},
    {"Olytics", ~w[oly_enc_id oly_anon_id]},
    {"Other", ~w[vero_id s_cid wickedid rb_clickid soc_src soc_trk]}
  ]

  # Flat set derived from the canonical list for fast membership checks.
  @tracking_params @tracking_params_by_source |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new()

  @doc "Returns the set of known tracking parameter names."
  @spec tracking_params() :: MapSet.t(String.t())
  def tracking_params, do: @tracking_params

  @doc """
  Returns tracking parameters grouped by source, for UI display.
  """
  @spec tracking_params_by_source() :: [{String.t(), [String.t()]}]
  def tracking_params_by_source, do: @tracking_params_by_source

  @doc """
  Normalizes a URL by downcasing the scheme and host for protocols that use
  DNS hostnames, and stripping known tracking query parameters.

  Default ports (80 for HTTP, 443 for HTTPS) are stripped.
  Schemes not known to use DNS hostnames are returned unchanged to avoid
  corrupting case-sensitive identifiers (e.g. IPFS content hashes).

  Returns the input unchanged for URLs without a host (e.g. `file:///path`)
  or for malformed input. The function is idempotent.

  ## Examples

      iex> Linkhut.Links.Url.normalize("HTTP://Example.COM/Path?q=1")
      "http://example.com/Path?q=1"

      iex> Linkhut.Links.Url.normalize("https://example.com:443/path")
      "https://example.com/path"

      iex> Linkhut.Links.Url.normalize("https://example.com/?q=elixir&fbclid=abc")
      "https://example.com/?q=elixir"

  """
  @spec normalize(String.t()) :: String.t()
  def normalize(url) when is_binary(url) do
    url
    |> normalize_host()
    |> strip_tracking_params()
  end

  @doc """
  Normalizes a URL by downcasing the scheme and host for protocols that use
  DNS hostnames.

  Default ports (80 for HTTP, 443 for HTTPS) are stripped.
  Schemes not known to use DNS hostnames are returned unchanged to avoid
  corrupting case-sensitive identifiers (e.g. IPFS content hashes).

  Returns the input unchanged for URLs without a host (e.g. `file:///path`)
  or for malformed input. The function is idempotent.

  ## Examples

      iex> Linkhut.Links.Url.normalize_host("HTTP://Example.COM/Path?q=1")
      "http://example.com/Path?q=1"

      iex> Linkhut.Links.Url.normalize_host("https://example.com:443/path")
      "https://example.com/path"

      iex> Linkhut.Links.Url.normalize_host("ipfs://QmAbCdEf/path")
      "ipfs://QmAbCdEf/path"

  """
  @spec normalize_host(String.t()) :: String.t()
  def normalize_host(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when is_binary(host) and scheme in @dns_schemes ->
        %URI{uri | host: String.downcase(host)}
        |> URI.to_string()

      _ ->
        url
    end
  end

  @doc """
  Removes known tracking query parameters from a URL string.
  Returns the URL unchanged if it has no query string or no tracking params.
  """
  @spec strip_tracking_params(String.t()) :: String.t()
  def strip_tracking_params(url) when is_binary(url) do
    uri = URI.parse(url)

    case uri.query do
      nil ->
        url

      "" ->
        url

      query ->
        cleaned =
          query
          |> String.split("&")
          |> Enum.reject(&tracking_param?/1)
          |> Enum.join("&")

        case cleaned do
          ^query -> url
          "" -> %URI{uri | query: nil} |> URI.to_string()
          _ -> %URI{uri | query: cleaned} |> URI.to_string()
        end
    end
  end

  defp tracking_param?(segment) do
    key =
      case String.split(segment, "=", parts: 2) do
        [k, _] -> k
        [k] -> k
      end

    decoded = URI.decode(key)
    MapSet.member?(@tracking_params, decoded)
  end
end
