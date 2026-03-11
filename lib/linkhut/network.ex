defmodule Linkhut.Network do
  @moduledoc """
  Network utility functions.
  """

  # Reserved/non-routable CIDR blocks with descriptive labels, parsed at compile time.
  @reserved_ranges [
                     # IPv4
                     {"0.0.0.0/8", :unspecified},
                     {"10.0.0.0/8", :private},
                     {"100.64.0.0/10", :shared},
                     {"127.0.0.0/8", :loopback},
                     {"169.254.0.0/16", :link_local},
                     {"172.16.0.0/12", :private},
                     {"192.0.0.0/24", :ietf_protocol},
                     {"192.0.2.0/24", :documentation},
                     {"192.168.0.0/16", :private},
                     {"198.18.0.0/15", :benchmarking},
                     {"198.51.100.0/24", :documentation},
                     {"203.0.113.0/24", :documentation},
                     {"240.0.0.0/4", :reserved},
                     # IPv6
                     {"::1/128", :loopback},
                     {"100::/64", :discard},
                     {"2001:db8::/32", :documentation},
                     {"fc00::/7", :private},
                     {"fe80::/10", :link_local}
                   ]
                   |> Enum.map(fn {cidr, label} -> {InetCidr.parse_cidr!(cidr), label} end)

  @doc """
  Returns `true` if the given hostname resolves to a globally routable address.

  Returns `false` for reserved/private/loopback addresses and when DNS
  resolution fails (safe default — block requests to unresolvable hosts).
  """
  @spec allowed_address?(String.t()) :: boolean()
  def allowed_address?(host) when is_binary(host) do
    case check_address(host) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @doc """
  Checks whether the given hostname resolves to a globally routable address.

  Returns `:ok` for allowed addresses, or `{:error, reason}` where reason
  describes why the address was blocked:

    - `{:dns_failed, host}` — hostname could not be resolved
    - `{:reserved, label, host}` — resolved to a reserved range, where label
      is one of: `:loopback`, `:private`, `:link_local`, `:shared`,
      `:documentation`, `:unspecified`, `:reserved`, `:ietf_protocol`,
      `:benchmarking`, `:discard`
  """
  @spec check_address(String.t()) :: :ok | {:error, term()}
  def check_address(host) when is_binary(host) do
    case :inet.getaddr(to_charlist(host), :inet) do
      {:ok, address} ->
        check_resolved(address, host)

      {:error, _} ->
        case :inet.getaddr(to_charlist(host), :inet6) do
          {:ok, address} -> check_resolved(address, host)
          {:error, _} -> {:error, {:dns_failed, host}}
        end
    end
  end

  defp check_resolved(address, host) do
    case reserved_range(address) do
      nil -> :ok
      label -> {:error, {:reserved, label, host}}
    end
  end

  # Unspecified IPv6 address
  defp reserved_range({0, 0, 0, 0, 0, 0, 0, 0}), do: :unspecified

  # ::ffff:0:0/96 — IPv4-mapped; extract embedded IPv4 and re-check
  defp reserved_range({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: reserved_range({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  # 64:ff9b::/96 — NAT64 well-known prefix; embeds IPv4 in last 32 bits
  defp reserved_range({0x0064, 0xFF9B, 0, 0, 0, 0, hi, lo}),
    do: reserved_range({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  # 2001::/32 — Teredo; client IPv4 in last 32 bits, XOR'd with 0xFFFFFFFF
  defp reserved_range({0x2001, 0x0000, _, _, _, _, hi, lo}),
    do:
      reserved_range(
        {255 - div(hi, 256), 255 - rem(hi, 256), 255 - div(lo, 256), 255 - rem(lo, 256)}
      )

  # 2002::/16 — 6to4; embeds IPv4 in bits 16–47 (segments 2–3)
  defp reserved_range({0x2002, hi, lo, _, _, _, _, _}),
    do: reserved_range({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  defp reserved_range(address) do
    Enum.find_value(@reserved_ranges, fn {cidr, label} ->
      if InetCidr.contains?(cidr, address), do: label
    end)
  end

  # Schemes known to use DNS hostnames (case-insensitive per RFC 1034 §3.1).
  @dns_schemes ~w(http https ftp gemini gopher)

  @doc """
  Normalizes a URL by downcasing the scheme and host for protocols that use
  DNS hostnames.

  Default ports (80 for HTTP, 443 for HTTPS) are stripped.
  Schemes not known to use DNS hostnames are returned unchanged to avoid
  corrupting case-sensitive identifiers (e.g. IPFS content hashes).

  Returns the input unchanged for URLs without a host (e.g. `file:///path`)
  or for malformed input. The function is idempotent.

  ## Examples

      iex> Linkhut.Network.normalize_url("HTTP://Example.COM/Path?q=1")
      "http://example.com/Path?q=1"

      iex> Linkhut.Network.normalize_url("https://example.com:443/path")
      "https://example.com/path"

      iex> Linkhut.Network.normalize_url("ipfs://QmAbCdEf/path")
      "ipfs://QmAbCdEf/path"

  """
  @spec normalize_url(String.t()) :: String.t()
  def normalize_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when is_binary(host) and scheme in @dns_schemes ->
        %URI{uri | host: String.downcase(host)}
        |> URI.to_string()

      _ ->
        url
    end
  end
end
