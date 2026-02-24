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
end
