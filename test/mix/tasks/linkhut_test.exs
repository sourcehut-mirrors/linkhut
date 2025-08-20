defmodule Mix.Tasks.LinkhutTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @moduletag :mix_task

  describe "run/1" do
    test "displays help with version and available tasks when called without arguments" do
      output = capture_io(fn -> Mix.Tasks.Linkhut.run([]) end)

      version = Mix.Project.config()[:version]

      assert output =~ "Linkhut v#{version}"
      assert output =~ "An open source social bookmarking website."
      assert output =~ "Available tasks:"
    end

    test "raises error for invalid arguments" do
      invalid_args = [
        ["invalid"],
        ["arg1", "arg2"]
      ]

      for args <- invalid_args do
        assert_raise Mix.Error, "Invalid arguments, expected: mix linkhut", fn ->
          Mix.Tasks.Linkhut.run(args)
        end
      end
    end
  end
end
