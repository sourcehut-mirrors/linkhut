defmodule Linkhut.Network do
  @moduledoc """
  Network utility functions.
  """

  @doc """
  Returns `true` if the given hostname resolves to a private/loopback address.

  Checks both IPv4 and IPv6. Returns `true` on DNS resolution failure
  (safe default — block requests to unresolvable hosts).
  """
  @spec local_address?(String.t()) :: boolean()
  def local_address?(host) when is_binary(host) do
    case :inet.getaddr(to_charlist(host), :inet) do
      {:ok, address} ->
        local_ip?(address)

      {:error, _} ->
        case :inet.getaddr(to_charlist(host), :inet6) do
          {:ok, address} -> local_ip?(address)
          {:error, _} -> true
        end
    end
  end

  defp local_ip?({127, _, _, _}), do: true
  defp local_ip?({10, _, _, _}), do: true
  defp local_ip?({192, 168, _, _}), do: true
  defp local_ip?({172, second, _, _}) when second >= 16 and second <= 31, do: true
  defp local_ip?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp local_ip?({0xFC00, _, _, _, _, _, _, _}), do: true
  defp local_ip?(_), do: false
end
