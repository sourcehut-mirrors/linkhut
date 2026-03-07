defmodule Linkhut.ConfigTest do
  use Linkhut.DataCase

  alias Linkhut.Config

  describe "archiving/2" do
    test "returns configured value" do
      assert Config.archiving(:mode) == :limited
    end

    test "returns default when key is missing" do
      assert Config.archiving(:nonexistent, :fallback) == :fallback
    end
  end

  describe "mail/2" do
    test "returns configured value" do
      assert Config.mail(:sender) == {"linkhut", "no-reply@example.com"}
    end

    test "returns default when key is missing" do
      assert Config.mail(:nonexistent) == nil
    end
  end

  describe "ifttt/2" do
    test "returns configured value" do
      assert Config.ifttt(:service_key) == "cccddd"
    end

    test "returns default when key is missing" do
      assert Config.ifttt(:nonexistent, :fallback) == :fallback
    end
  end

  describe "prometheus/2" do
    test "returns default when unconfigured" do
      assert Config.prometheus(:username) == nil
    end

    test "returns default when key is missing" do
      assert Config.prometheus(:nonexistent, :fallback) == :fallback
    end
  end
end
