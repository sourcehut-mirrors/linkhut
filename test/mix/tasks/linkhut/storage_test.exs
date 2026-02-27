defmodule Mix.Tasks.Linkhut.StorageTest do
  use Linkhut.DataCase, async: false

  import Linkhut.Factory

  alias Linkhut.Archiving.Archive

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

    test "recompute updates archive sizes and shows stats" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, user_id: user.id, link_id: link.id, url: link.url)

      insert(:snapshot,
        user_id: user.id,
        link_id: link.id,
        archive_id: archive.id,
        state: :complete,
        file_size_bytes: 3000
      )

      Mix.Tasks.Linkhut.Storage.run(["recompute"])

      updated = Repo.get(Archive, archive.id)
      assert updated.total_size_bytes == 3000

      assert_received {:mix_shell, :info, ["Recomputing all archive sizes..."]}
      assert_received {:mix_shell, :info, ["Done."]}
    end

    test "shows error for invalid arguments" do
      Mix.Tasks.Linkhut.Storage.run(["invalid"])

      assert_received {:mix_shell, :error, [msg]}
      assert msg =~ "Usage:"
    end
  end
end
