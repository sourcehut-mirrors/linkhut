defmodule Linkhut.NetworkTest do
  use ExUnit.Case, async: true

  alias Linkhut.Network

  describe "allowed_address?/1" do
    test "returns false for localhost" do
      refute Network.allowed_address?("localhost")
    end

    test "returns false for 127.0.0.1" do
      refute Network.allowed_address?("127.0.0.1")
    end

    test "returns false for unresolvable hosts" do
      refute Network.allowed_address?("this.host.does.not.exist.invalid")
    end

    test "returns true for public hosts" do
      assert Network.allowed_address?("example.com")
    end
  end

  describe "check_address/1" do
    test "returns :ok for public hosts" do
      assert Network.check_address("example.com") == :ok
    end

    test "returns loopback reason for localhost" do
      assert {:error, {:reserved, :loopback, "localhost"}} = Network.check_address("localhost")
    end

    test "returns loopback reason for 127.0.0.1" do
      assert {:error, {:reserved, :loopback, "127.0.0.1"}} = Network.check_address("127.0.0.1")
    end

    test "returns dns_failed for unresolvable hosts" do
      host = "this.host.does.not.exist.invalid"
      assert {:error, {:dns_failed, ^host}} = Network.check_address(host)
    end

    test "returns private reason for RFC 1918 addresses" do
      assert {:error, {:reserved, :private, "10.0.0.1"}} = Network.check_address("10.0.0.1")
      assert {:error, {:reserved, :private, "192.168.1.1"}} = Network.check_address("192.168.1.1")
      assert {:error, {:reserved, :private, "172.16.0.1"}} = Network.check_address("172.16.0.1")
    end

    test "returns link_local reason for 169.254.x.x" do
      assert {:error, {:reserved, :link_local, "169.254.1.1"}} =
               Network.check_address("169.254.1.1")
    end
  end

  describe "normalize_url/1" do
    test "lowercases host for HTTP URLs" do
      assert Network.normalize_url("http://EXAMPLE.COM/Path") == "http://example.com/Path"
    end

    test "lowercases host for HTTPS URLs" do
      assert Network.normalize_url("https://Example.COM/Path") == "https://example.com/Path"
    end

    test "lowercases scheme" do
      assert Network.normalize_url("HTTP://example.com") == "http://example.com"
      assert Network.normalize_url("HTTPS://example.com") == "https://example.com"
    end

    test "strips default ports" do
      assert Network.normalize_url("http://example.com:80/path") == "http://example.com/path"
      assert Network.normalize_url("https://example.com:443/path") == "https://example.com/path"
    end

    test "preserves non-default ports" do
      assert Network.normalize_url("http://example.com:8080/path") ==
               "http://example.com:8080/path"
    end

    test "preserves path, query, and fragment" do
      assert Network.normalize_url("https://Example.COM/Path?q=1&b=2#frag") ==
               "https://example.com/Path?q=1&b=2#frag"
    end

    test "is idempotent" do
      url = "https://example.com/path?q=1"
      assert Network.normalize_url(url) == url
      assert Network.normalize_url(Network.normalize_url(url)) == url
    end

    test "returns unchanged for URLs without a host" do
      assert Network.normalize_url("file:///some/path") == "file:///some/path"
    end

    test "returns unchanged for malformed input" do
      assert Network.normalize_url("not a url") == "not a url"
    end

    test "normalizes other DNS-based schemes" do
      assert Network.normalize_url("ftp://FTP.Example.COM/pub") == "ftp://ftp.example.com/pub"
      assert Network.normalize_url("gemini://EXAMPLE.COM/page") == "gemini://example.com/page"
      assert Network.normalize_url("gopher://EXAMPLE.COM/1") == "gopher://example.com/1"
    end

    test "does not lowercase host for unknown schemes" do
      assert Network.normalize_url("ipfs://QmAbCdEf/path") == "ipfs://QmAbCdEf/path"
    end
  end
end
