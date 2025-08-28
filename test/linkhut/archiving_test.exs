defmodule Linkhut.ArchivingTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot

  defp insert_oban_job do
    {:ok, job} =
      Linkhut.Workers.Archiver.new(%{"user_id" => 1, "link_id" => 1, "url" => "https://example.com"})
      |> Oban.insert()

    job
  end

  describe "create_snapshot/3" do
    test "creates a snapshot with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()

      assert {:ok, %Snapshot{} = snapshot} = Archiving.create_snapshot(link.id, job.id)
      assert snapshot.link_id == link.id
      assert snapshot.job_id == job.id
    end

    test "creates a snapshot with all fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()

      attrs = %{
        type: "singlefile",
        state: :complete,
        storage_key: "local:/tmp/test/archive",
        file_size_bytes: 2048,
        processing_time_ms: 300,
        response_code: 200
      }

      assert {:ok, %Snapshot{} = snapshot} = Archiving.create_snapshot(link.id, job.id, attrs)
      assert snapshot.type == "singlefile"
      assert snapshot.state == :complete
      assert snapshot.storage_key == "local:/tmp/test/archive"
      assert snapshot.file_size_bytes == 2048
    end
  end

  describe "get_snapshot/2" do
    test "returns snapshot by link_id and job_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()
      {:ok, snapshot} = Archiving.create_snapshot(link.id, job.id, %{type: "singlefile"})

      found = Archiving.get_snapshot(link.id, snapshot.job_id)
      assert found.id == snapshot.id
    end

    test "returns nil when not found" do
      assert nil == Archiving.get_snapshot(999, 999)
    end
  end

  describe "update_snapshot/2" do
    test "updates snapshot fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()
      {:ok, snapshot} = Archiving.create_snapshot(link.id, job.id)

      assert {:ok, updated} =
               Archiving.update_snapshot(snapshot, %{state: :complete, storage_key: "local:/tmp/done"})

      assert updated.state == :complete
      assert updated.storage_key == "local:/tmp/done"
    end
  end
end
