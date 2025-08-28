defmodule Linkhut.NetworkTest do
  use ExUnit.Case, async: true

  alias Linkhut.Network

  describe "local_address?/1" do
    test "returns true for localhost" do
      assert Network.local_address?("localhost")
    end

    test "returns true for 127.0.0.1" do
      assert Network.local_address?("127.0.0.1")
    end

    test "returns true for unresolvable hosts" do
      assert Network.local_address?("this.host.does.not.exist.invalid")
    end

    test "returns false for public hosts" do
      refute Network.local_address?("example.com")
    end
  end
end
