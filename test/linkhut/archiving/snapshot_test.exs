defmodule Linkhut.Archiving.SnapshotTest do
  use Linkhut.DataCase

  alias Linkhut.Archiving.Snapshot

  describe "create_changeset/2" do
    test "valid with required fields" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, user_id: 1, archive_id: 1})
      assert changeset.valid?
    end

    test "valid with all fields" do
      attrs = %{
        link_id: 1,
        user_id: 1,
        job_id: 2,
        archive_id: 3,
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

      changeset = Snapshot.create_changeset(%Snapshot{}, attrs)
      assert changeset.valid?
    end

    test "invalid without link_id" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{user_id: 1, archive_id: 1})
      refute changeset.valid?
      assert %{link_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without user_id" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, archive_id: 1})
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without archive_id" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, user_id: 1})
      refute changeset.valid?
      assert %{archive_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults state to :pending" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, user_id: 1, archive_id: 1})
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.state == :pending
    end

    test "defaults retry_count to 0" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, user_id: 1, archive_id: 1})
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.retry_count == 0
    end

    test "casts crawler_meta" do
      attrs = %{
        link_id: 1,
        user_id: 1,
        archive_id: 1,
        crawler_meta: %{tool_name: "SingleFile", version: "1.0.0"}
      }

      changeset = Snapshot.create_changeset(%Snapshot{}, attrs)
      assert changeset.valid?
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.crawler_meta == %{"tool_name" => "SingleFile", "version" => "1.0.0"}
    end

    test "defaults crawler_meta to empty map" do
      changeset = Snapshot.create_changeset(%Snapshot{}, %{link_id: 1, user_id: 1, archive_id: 1})
      snapshot = Ecto.Changeset.apply_changes(changeset)
      assert snapshot.crawler_meta == %{}
    end
  end

  describe "update_changeset/2" do
    test "does not cast crawler_meta" do
      changeset =
        Snapshot.update_changeset(%Snapshot{crawler_meta: %{"tool_name" => "Original"}}, %{
          crawler_meta: %{"tool_name" => "Changed"}
        })

      # crawler_meta is not in @updatable_fields, so it should not be cast
      refute Map.has_key?(changeset.changes, :crawler_meta)
    end
  end
end
