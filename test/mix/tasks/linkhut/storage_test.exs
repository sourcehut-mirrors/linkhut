defmodule Mix.Tasks.Linkhut.StorageTest do
  use Linkhut.DataCase, async: false

  import Linkhut.Factory

  @moduletag :mix_task

  defp setup_shell(_context) do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  describe "run/1" do
    setup :setup_shell

    test "shows storage stats" do
      Mix.Tasks.Linkhut.Storage.run([])

      assert_received {:mix_shell, :info, [db_msg]}
      assert db_msg =~ "Storage (DB total):"
      assert_received {:mix_shell, :info, [disk_msg]}
      assert disk_msg =~ "Storage (disk total):"
    end

    test "shows error for invalid arguments" do
      Mix.Tasks.Linkhut.Storage.run(["invalid"])

      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "Usage:"
    end
  end
end
