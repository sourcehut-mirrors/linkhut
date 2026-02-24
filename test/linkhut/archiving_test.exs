defmodule Linkhut.ArchivingTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Snapshot}
  alias Linkhut.Archiving.Workers.Archiver

  defp set_archiving_mode(mode) do
    config = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.put(config[:archiving], :mode, mode)
    Application.put_env(:linkhut, Linkhut, Keyword.put(config, :archiving, archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, config)
    end)
  end

  describe "enabled_for_user?/1" do
    test "returns false for all users when disabled" do
      set_archiving_mode(:disabled)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns true only for paying users when limited" do
      set_archiving_mode(:limited)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns true for all active users when enabled" do
      set_archiving_mode(:enabled)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns false for nil" do
      assert Archiving.enabled_for_user?(nil) == false
    end
  end

  describe "get_or_create_archive/4" do
    test "creates archive with job_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      {:ok, job} = insert_oban_job()

      assert {:ok, %Archive{} = archive} =
               Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert archive.link_id == link.id
      assert archive.user_id == user.id
      assert archive.url == link.url
      assert archive.state == :active
    end

    test "returns existing archive on repeated call (idempotent)" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      {:ok, job} = insert_oban_job()

      {:ok, archive1} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)
      {:ok, archive2} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert archive1.id == archive2.id
    end
  end

  describe "mark_old_archives_for_deletion/2" do
    test "marks active archives for deletion, excluding specified IDs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, job1} = insert_oban_job()
      {:ok, job2} = insert_oban_job()

      {:ok, old_archive} = Archiving.get_or_create_archive(job1.id, link.id, user.id, link.url)
      {:ok, new_archive} = Archiving.get_or_create_archive(job2.id, link.id, user.id, link.url)

      :ok = Archiving.mark_old_archives_for_deletion(link.id, exclude: [new_archive.id])

      assert Repo.get(Archive, old_archive.id).state == :pending_deletion
      assert Repo.get(Archive, new_archive.id).state == :active
    end
  end

  describe "create_snapshot/4" do
    test "creates a snapshot with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Snapshot{} = snapshot} = Archiving.create_snapshot(link.id, user.id, nil)
      assert snapshot.link_id == link.id
      assert snapshot.user_id == user.id
    end

    test "creates a snapshot with all fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      attrs = %{
        type: "singlefile",
        state: :complete,
        storage_key: "local:/tmp/test/archive",
        file_size_bytes: 2048,
        processing_time_ms: 300,
        response_code: 200
      }

      assert {:ok, %Snapshot{} = snapshot} =
               Archiving.create_snapshot(link.id, user.id, nil, attrs)

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
      {:ok, job} = insert_oban_job()

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, job.id, %{type: "singlefile"})

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
      {:ok, snapshot} = Archiving.create_snapshot(link.id, user.id, nil)

      assert {:ok, updated} =
               Archiving.update_snapshot(snapshot, %{
                 state: :complete,
                 storage_key: "local:/tmp/done"
               })

      assert updated.state == :complete
      assert updated.storage_key == "local:/tmp/done"
    end
  end

  describe "mark_snapshots_for_deletion/1" do
    test "marks all snapshots for a link as pending_deletion" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, s1} = Archiving.create_snapshot(link.id, user.id, nil, %{state: :complete})
      {:ok, s2} = Archiving.create_snapshot(link.id, user.id, nil, %{state: :pending})

      assert {2, _} = Archiving.mark_snapshots_for_deletion(link.id)

      assert Repo.get(Snapshot, s1.id).state == :pending_deletion
      assert Repo.get(Snapshot, s2.id).state == :pending_deletion
    end

    test "does not affect snapshots for other links" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)

      {:ok, _} = Archiving.create_snapshot(link1.id, user.id, nil, %{state: :complete})
      {:ok, s2} = Archiving.create_snapshot(link2.id, user.id, nil, %{state: :complete})

      Archiving.mark_snapshots_for_deletion(link1.id)

      assert Repo.get(Snapshot, s2.id).state == :complete
    end
  end

  describe "enqueue_pending_deletions/0" do
    test "enqueues a SnapshotDeleter job for each pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, s1} =
        Archiving.create_snapshot(link.id, user.id, nil, %{state: :pending_deletion})

      {:ok, s2} =
        Archiving.create_snapshot(link.id, user.id, nil, %{state: :pending_deletion})

      assert :ok = Archiving.enqueue_pending_deletions()

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.SnapshotDeleter,
        args: %{"snapshot_id" => s1.id}
      )

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.SnapshotDeleter,
        args: %{"snapshot_id" => s2.id}
      )
    end

    test "does not enqueue jobs for non-pending_deletion snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{state: :complete})

      assert :ok = Archiving.enqueue_pending_deletions()

      refute_enqueued(worker: Linkhut.Archiving.Workers.SnapshotDeleter)
    end
  end

  describe "delete_snapshot/1" do
    @data_dir Linkhut.Config.archiving(:data_dir)

    setup do
      File.rm_rf!(@data_dir)
      File.mkdir_p!(@data_dir)
      on_exit(fn -> File.rm_rf(@data_dir) end)
      :ok
    end

    test "deletes storage and record for pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      path = Path.join(@data_dir, "1/100/singlefile/12345/archive")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :pending_deletion,
          storage_key: "local:" <> path
        })

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
      refute File.exists?(path)
    end

    test "deletes record when storage_key is nil" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, nil, %{state: :pending_deletion})

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
    end

    test "returns :ok when snapshot does not exist" do
      assert :ok = Archiving.delete_snapshot(999_999)
    end

    test "returns error when storage deletion fails" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :pending_deletion,
          storage_key: "cloud:bucket/key"
        })

      assert {:error, :invalid_storage_key} = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) != nil
    end
  end

  describe "storage_used/0" do
    test "returns 0 when no snapshots exist" do
      assert Archiving.storage_used() == 0
    end

    test "sums only complete snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :complete,
          file_size_bytes: 1000
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :complete,
          file_size_bytes: 2000
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :failed,
          file_size_bytes: 500
        })

      assert Archiving.storage_used() == 3000
    end
  end

  describe "storage_used_by_user/1" do
    test "returns bytes for a specific user" do
      user1 = insert(:user, credential: build(:credential))
      user2 = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user1.id)
      link2 = insert(:link, user_id: user2.id)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user1.id, nil, %{
          state: :complete,
          file_size_bytes: 1000
        })

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user2.id, nil, %{
          state: :complete,
          file_size_bytes: 2000
        })

      assert Archiving.storage_used_by_user(user1.id) == 1000
    end

    test "returns 0 for user with no snapshots" do
      user = insert(:user, credential: build(:credential))
      assert Archiving.storage_used_by_user(user.id) == 0
    end
  end

  describe "merge_timeline/2" do
    test "merges archive and crawler steps chronologically" do
      archive_steps = [
        %{"step" => "created", "at" => "2026-02-26T10:00:00Z"},
        %{"step" => "preflight", "detail" => "text/html; 200", "at" => "2026-02-26T10:00:01Z"},
        %{"step" => "dispatched", "detail" => "singlefile", "at" => "2026-02-26T10:00:02Z"}
      ]

      snapshot = %{
        type: "singlefile",
        crawl_info: %{
          "steps" => [
            %{"step" => "crawling", "at" => "2026-02-26T10:00:03Z"},
            %{"step" => "complete", "detail" => "Stored 1.5MB", "at" => "2026-02-26T10:00:10Z"}
          ]
        }
      }

      timeline = Archiving.merge_timeline(archive_steps, [snapshot])

      assert length(timeline) == 5
      step_names = Enum.map(timeline, & &1["step"])
      assert step_names == ["created", "preflight", "dispatched", "crawling", "complete"]

      # Crawler steps should have prefix
      assert Enum.at(timeline, 3)["prefix"] == "singlefile"
      assert Enum.at(timeline, 4)["prefix"] == "singlefile"

      # Archive steps should not have prefix
      refute Enum.at(timeline, 0)["prefix"]
    end

    test "handles empty archive steps" do
      snapshot = %{
        type: "singlefile",
        crawl_info: %{
          "steps" => [%{"step" => "crawling", "at" => "2026-02-26T10:00:00Z"}]
        }
      }

      timeline = Archiving.merge_timeline([], [snapshot])
      assert length(timeline) == 1
      assert hd(timeline)["prefix"] == "singlefile"
    end

    test "handles snapshots without crawl_info" do
      archive_steps = [%{"step" => "created", "at" => "2026-02-26T10:00:00Z"}]
      snapshot = %{type: "singlefile", crawl_info: nil}

      timeline = Archiving.merge_timeline(archive_steps, [snapshot])
      assert length(timeline) == 1
    end

    test "handles nil archive steps" do
      snapshot = %{type: "singlefile", crawl_info: nil}

      timeline = Archiving.merge_timeline(nil, [snapshot])
      assert timeline == []
    end

    test "merges steps from multiple snapshots with prefixes" do
      archive_steps = [
        %{"step" => "created", "at" => "2026-02-26T10:00:00Z"},
        %{"step" => "dispatched", "at" => "2026-02-26T10:00:01Z"}
      ]

      snapshot1 = %{
        type: "singlefile",
        crawl_info: %{
          "steps" => [%{"step" => "crawling", "at" => "2026-02-26T10:00:02Z"}]
        }
      }

      snapshot2 = %{
        type: "wget",
        crawl_info: %{
          "steps" => [%{"step" => "crawling", "at" => "2026-02-26T10:00:03Z"}]
        }
      }

      timeline = Archiving.merge_timeline(archive_steps, [snapshot1, snapshot2])
      assert length(timeline) == 4

      prefixes = Enum.map(timeline, & &1["prefix"])
      assert prefixes == [nil, nil, "singlefile", "wget"]
    end
  end

  describe "list_unarchived_links_for_user/2" do
    test "returns links with no complete snapshots or active archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      result = Archiving.list_unarchived_links_for_user(user)
      assert [returned] = result
      assert returned.id == link.id
    end

    test "excludes links with a complete snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{
          state: :complete,
          storage_key: "local:/tmp/test"
        })

      assert Archiving.list_unarchived_links_for_user(user) == []
    end

    test "excludes links with an active archive" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      {:ok, job} = insert_oban_job(link_id: link.id, user_id: user.id)
      {:ok, _archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)

      assert Archiving.list_unarchived_links_for_user(user) == []
    end

    test "includes links with only failed snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, nil, %{state: :failed})

      result = Archiving.list_unarchived_links_for_user(user)
      assert [returned] = result
      assert returned.id == link.id
    end

    test "includes links with only failed archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      {:ok, job} = insert_oban_job(link_id: link.id, user_id: user.id)
      {:ok, archive} = Archiving.get_or_create_archive(job.id, link.id, user.id, link.url)
      Archiving.update_archive(archive, %{state: :failed})

      result = Archiving.list_unarchived_links_for_user(user)
      assert [returned] = result
      assert returned.id == link.id
    end

    test "does not return links belonging to other users" do
      user1 = insert(:user, credential: build(:credential))
      user2 = insert(:user, credential: build(:credential))
      _link1 = insert(:link, user_id: user1.id)
      _link2 = insert(:link, user_id: user2.id)

      result = Archiving.list_unarchived_links_for_user(user1)
      assert length(result) == 1
    end

    test "respects the limit parameter" do
      user = insert(:user, credential: build(:credential))
      for _ <- 1..5, do: insert(:link, user_id: user.id)

      result = Archiving.list_unarchived_links_for_user(user, 3)
      assert length(result) == 3
    end

    test "orders by inserted_at ascending" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)

      result = Archiving.list_unarchived_links_for_user(user)
      assert [first, second] = result
      assert first.id == link1.id
      assert second.id == link2.id
    end
  end

  defp insert_oban_job(opts \\ []) do
    Archiver.new(%{
      "user_id" => Keyword.get(opts, :user_id, 1),
      "link_id" => Keyword.get(opts, :link_id, System.unique_integer([:positive])),
      "url" => Keyword.get(opts, :url, "https://example.com")
    })
    |> Oban.insert()
  end
end
