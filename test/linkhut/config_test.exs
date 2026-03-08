defmodule Linkhut.ConfigTest do
  use Linkhut.DataCase, async: true

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

  describe "put_override/3" do
    test "override takes precedence over Application config" do
      put_override(Linkhut.Archiving, :mode, :test_override)

      assert Config.archiving(:mode) == :test_override
    end

    test "different namespaces are independent" do
      put_override(Linkhut.Archiving, :mode, :archiving_value)
      put_override(Linkhut.IFTTT, :mode, :ifttt_value)

      assert Config.archiving(:mode) == :archiving_value
      assert Config.ifttt(:mode) == :ifttt_value
    end

    test "overrides propagate through Task.async via $callers" do
      put_override(Linkhut.Archiving, :mode, :from_parent)

      task =
        Task.async(fn ->
          Config.archiving(:mode)
        end)

      assert Task.await(task) == :from_parent
    end

    test "overrides propagate through nested Task.async" do
      put_override(Linkhut.Archiving, :mode, :from_grandparent)

      task =
        Task.async(fn ->
          inner_task =
            Task.async(fn ->
              Config.archiving(:mode)
            end)

          Task.await(inner_task)
        end)

      assert Task.await(task) == :from_grandparent
    end

    test "override can be set to nil" do
      put_override(Linkhut.Archiving, :mode, nil)
      assert Config.archiving(:mode) == nil
    end

    test "override can be set to false" do
      put_override(Linkhut.Archiving, :mode, false)
      assert Config.archiving(:mode) == false
    end

    test "overrides don't leak to unrelated processes" do
      put_override(Linkhut.Archiving, :mode, :should_not_leak)

      parent = self()

      spawn(fn ->
        send(parent, {:result, Config.archiving(:mode)})
      end)

      assert_receive {:result, value}
      refute value == :should_not_leak
    end
  end
end
