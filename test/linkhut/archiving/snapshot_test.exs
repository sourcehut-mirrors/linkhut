defmodule Linkhut.Archiving.SnapshotTest do
  use Linkhut.DataCase

  alias Linkhut.Archiving.Snapshot

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = Snapshot.changeset(%Snapshot{}, %{link_id: 1, job_id: 2})
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        link_id: 1,
        job_id: 2,
        type: "singlefile",
        state: :complete,
        storage_key: "local:/tmp/test",
        file_size_bytes: 1024,
        processing_time_ms: 500,
        response_code: 200,
        retry_count: 0,
        crawl_info: %{"cmd" => "single-file"},
        archive_metadata: %{"original_url" => "https://example.com"}
      }

      changeset = Snapshot.changeset(%Snapshot{}, attrs)
      assert changeset.valid?
    end

    test "invalid without link_id" do
      changeset = Snapshot.changeset(%Snapshot{}, %{job_id: 2})
      refute changeset.valid?
      assert %{link_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without job_id" do
      changeset = Snapshot.changeset(%Snapshot{}, %{link_id: 1})
      refute changeset.valid?
      assert %{job_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults state to :in_progress" do
      changeset = Snapshot.changeset(%Snapshot{}, %{link_id: 1, job_id: 2})
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.state == :in_progress
    end

    test "defaults retry_count to 0" do
      changeset = Snapshot.changeset(%Snapshot{}, %{link_id: 1, job_id: 2})
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.retry_count == 0
    end
  end
end
