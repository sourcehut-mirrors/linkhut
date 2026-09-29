defmodule Linkhut.Archiving.CleanupTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot

  defp snapshots(link, specs) do
    for {format, source, state} <- specs do
      insert(:snapshot,
        user_id: link.user_id,
        link_id: link.id,
        format: format,
        source: source,
        state: state
      )
    end
  end

  defp mark(link, {format, source}, state) do
    pending =
      insert(:snapshot,
        user_id: link.user_id,
        link_id: link.id,
        format: format,
        source: source,
        state: :pending
      )

    {:ok, snapshot} = Archiving.mark_snapshot(pending, state, %{})
    snapshot
  end

  defp states(snapshots), do: Enum.map(snapshots, &Repo.get(Snapshot, &1.id).state)

  setup do
    user = insert(:user, credential: build(:credential))
    %{link: insert(:link, user_id: user.id)}
  end

  describe "mark_snapshot/3 replaces older snapshots of the same link and format" do
    test "replaces older snapshots in the same or a worse state", %{link: link} do
      for {state, expected} <- [
            complete: [:pending_deletion, :pending_deletion, :pending_deletion],
            not_available: [:complete, :pending_deletion, :pending_deletion],
            failed: [:complete, :not_available, :pending_deletion]
          ] do
        link = insert(:link, user_id: link.user_id)

        older =
          snapshots(link, [
            {"webpage", "singlefile", :complete},
            {"webpage", "httpfetch", :not_available},
            {"webpage", "singlefile", :failed}
          ])

        mark(link, {"webpage", "singlefile"}, state)

        assert states(older) == expected, "for #{state}"
      end
    end
  end

  describe "mark_snapshot/3 on a snapshot marked for deletion while it was crawled" do
    test "remains as pending deletion", %{link: link} do
      [crawling] = snapshots(link, [{"webpage", "singlefile", :crawling}])
      :ok = Archiving.mark_snapshots_for_deletion(link.id)
      [older] = snapshots(link, [{"webpage", "singlefile", :failed}])

      assert {:ok, _} =
               Archiving.mark_snapshot(crawling, :complete, %{storage_key: "local:/tmp/x"})

      assert %{state: :pending_deletion, storage_key: "local:/tmp/x"} =
               Repo.get(Snapshot, crawling.id)

      assert states([older]) == [:failed]
    end
  end
end
