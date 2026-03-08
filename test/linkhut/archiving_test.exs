defmodule Linkhut.ArchivingTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Archive, Snapshot}

  defp create_archive(user, link) do
    insert(:archive, user_id: user.id, link_id: link.id, url: link.url)
  end

  describe "enabled_for_user?/1" do
    test "returns false for all users when disabled" do
      put_override(Linkhut.Archiving, :mode, :disabled)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns true only for paying users when limited" do
      put_override(Linkhut.Archiving, :mode, :limited)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == false
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns true for all active users when enabled" do
      put_override(Linkhut.Archiving, :mode, :enabled)

      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_paying}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :active_free}) == true
      assert Archiving.enabled_for_user?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
    end

    test "returns false for nil" do
      assert Archiving.enabled_for_user?(nil) == false
    end
  end

  describe "create_archive/1" do
    test "creates archive with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Archive{} = archive} =
               Archiving.create_archive(%{
                 link_id: link.id,
                 user_id: user.id,
                 url: link.url,
                 state: :pending
               })

      assert archive.link_id == link.id
      assert archive.user_id == user.id
      assert archive.url == link.url
      assert archive.state == :pending
    end
  end

  describe "start_processing/1" do
    test "transitions pending archive to processing" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :pending
        )

      assert {:ok, processing} = Archiving.start_processing(archive.id)
      assert processing.state == :processing
    end

    test "is idempotent for already-processing archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      assert {:ok, same} = Archiving.start_processing(archive.id)
      assert same.id == archive.id
      assert same.state == :processing
    end

    test "returns error for non-existent archive" do
      assert {:error, :not_found} = Archiving.start_processing(999_999)
    end

    test "returns error for failed archive" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :failed
        )

      assert {:error, :not_found} = Archiving.start_processing(archive.id)
    end
  end

  describe "mark_old_archives_for_deletion/2" do
    test "marks archives in all states for deletion, excluding specified IDs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      processing_archive = create_archive(user, link)

      complete_archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :complete)

      failed_archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :failed)

      pending_archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :pending)

      excluded_archive = create_archive(user, link)

      :ok = Archiving.mark_old_archives_for_deletion(link.id, exclude: [excluded_archive.id])

      assert Repo.get(Archive, processing_archive.id).state == :pending_deletion
      assert Repo.get(Archive, complete_archive.id).state == :pending_deletion
      assert Repo.get(Archive, failed_archive.id).state == :pending_deletion
      assert Repo.get(Archive, pending_archive.id).state == :pending_deletion
      assert Repo.get(Archive, excluded_archive.id).state == :processing
    end
  end

  describe "create_snapshot/3" do
    test "creates a snapshot with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      assert {:ok, %Snapshot{} = snapshot} =
               Archiving.create_snapshot(link.id, user.id, %{archive_id: archive.id})

      assert snapshot.link_id == link.id
      assert snapshot.user_id == user.id
      assert snapshot.archive_id == archive.id
    end

    test "creates a snapshot with all fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      attrs = %{
        archive_id: archive.id,
        type: "singlefile",
        state: :complete,
        storage_key: "local:/tmp/test/archive",
        file_size_bytes: 2048,
        processing_time_ms: 300,
        response_code: 200
      }

      assert {:ok, %Snapshot{} = snapshot} =
               Archiving.create_snapshot(link.id, user.id, attrs)

      assert snapshot.type == "singlefile"
      assert snapshot.state == :complete
      assert snapshot.storage_key == "local:/tmp/test/archive"
      assert snapshot.file_size_bytes == 2048
    end

    test "rejects snapshot without archive_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:error, changeset} = Archiving.create_snapshot(link.id, user.id)
      assert %{archive_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_snapshot/2" do
    test "returns snapshot by link_id and job_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      # Create a real Oban job to satisfy the FK constraint
      {:ok, oban_job} =
        Linkhut.Archiving.Workers.Archiver.new(%{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => link.url,
          "archive_id" => archive.id
        })
        |> Oban.insert()

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          archive_id: archive.id,
          job_id: oban_job.id
        })

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
      archive = create_archive(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{archive_id: archive.id})

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
      archive = create_archive(user, link)

      {:ok, s1} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending,
          archive_id: archive.id
        })

      assert :ok = Archiving.mark_snapshots_for_deletion(link.id)

      assert Repo.get(Snapshot, s1.id).state == :pending_deletion
      assert Repo.get(Snapshot, s2.id).state == :pending_deletion
    end

    test "does not affect snapshots for other links" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)
      archive1 = create_archive(user, link1)
      archive2 = create_archive(user, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user.id, %{
          state: :complete,
          archive_id: archive1.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link2.id, user.id, %{
          state: :complete,
          archive_id: archive2.id
        })

      Archiving.mark_snapshots_for_deletion(link1.id)

      assert Repo.get(Snapshot, s2.id).state == :complete
    end
  end

  describe "enqueue_pending_deletions/0" do
    test "enqueues a SnapshotDeleter job for each pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      {:ok, s1} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          archive_id: archive.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          archive_id: archive.id
        })

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
      archive = create_archive(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

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
      archive = create_archive(user, link)

      path = Path.join(@data_dir, "1/100/10/42.singlefile")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          storage_key: "local:" <> path,
          archive_id: archive.id
        })

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
      refute File.exists?(path)
    end

    test "deletes record when storage_key is nil" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          archive_id: archive.id
        })

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
    end

    test "returns :ok when snapshot does not exist" do
      assert :ok = Archiving.delete_snapshot(999_999)
    end

    test "returns error when storage deletion fails" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          storage_key: "cloud:bucket/key",
          archive_id: archive.id
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
      archive = create_archive(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          file_size_bytes: 500,
          archive_id: archive.id
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
      archive1 = create_archive(user1, link1)
      archive2 = create_archive(user2, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user1.id, %{
          state: :complete,
          file_size_bytes: 1000,
          archive_id: archive1.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user2.id, %{
          state: :complete,
          file_size_bytes: 2000,
          archive_id: archive2.id
        })

      assert Archiving.storage_used_by_user(user1.id) == 1000
    end

    test "returns 0 for user with no snapshots" do
      user = insert(:user, credential: build(:credential))
      assert Archiving.storage_used_by_user(user.id) == 0
    end
  end

  describe "recompute_archive_size/1" do
    test "sums only complete snapshots for an archive" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      archive = create_archive(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          file_size_bytes: 500,
          archive_id: archive.id
        })

      Archiving.recompute_archive_size(archive)

      updated = Repo.get(Archive, archive.id)
      assert updated.total_size_bytes == 3000
    end
  end

  describe "recompute_archive_size_by_id/1" do
    test "returns :ok for nil" do
      assert :ok = Archiving.recompute_archive_size_by_id(nil)
    end

    test "returns :ok for non-existent archive ID" do
      assert :ok = Archiving.recompute_archive_size_by_id(999_999)
    end
  end

  describe "recompute_all_archive_sizes/0" do
    test "bulk updates multiple archives" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)
      archive1 = create_archive(user, link1)
      archive2 = create_archive(user, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          archive_id: archive1.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          archive_id: archive2.id
        })

      assert :ok = Archiving.recompute_all_archive_sizes()

      assert Repo.get(Archive, archive1.id).total_size_bytes == 1000
      assert Repo.get(Archive, archive2.id).total_size_bytes == 2000
    end

    test "zeros stale values for archives with no complete snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          total_size_bytes: 5000
        )

      assert :ok = Archiving.recompute_all_archive_sizes()

      assert Repo.get(Archive, archive.id).total_size_bytes == 0
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

      # Crawler steps share a group starting at 1, archive steps have no group
      refute Enum.at(timeline, 0)["group"]
      assert Enum.at(timeline, 3)["group"] == 1
      assert Enum.at(timeline, 4)["group"] == 1
    end

    test "handles snapshots without crawl_info" do
      archive_steps = [%{"step" => "created", "at" => "2026-02-26T10:00:00Z"}]
      snapshot = %{type: "singlefile", crawl_info: nil}

      timeline = Archiving.merge_timeline(archive_steps, [snapshot])
      assert length(timeline) == 1
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

    test "keeps crawler groups together when interleaved with archive steps" do
      archive_steps = [
        %{"step" => "created", "at" => "2026-02-26T10:00:00Z"},
        %{"step" => "dispatched", "at" => "2026-02-26T10:00:01Z"},
        %{"step" => "complete", "at" => "2026-02-26T10:00:20Z"}
      ]

      # singlefile starts at t=02, finishes at t=15 (spans past wayback's start)
      snapshot1 = %{
        type: "singlefile",
        crawl_info: %{
          "steps" => [
            %{"step" => "crawling", "at" => "2026-02-26T10:00:02Z"},
            %{"step" => "stored", "at" => "2026-02-26T10:00:15Z"}
          ]
        }
      }

      # wayback starts at t=05, finishes at t=06 (between singlefile's steps)
      snapshot2 = %{
        type: "wayback",
        crawl_info: %{
          "steps" => [
            %{"step" => "crawling", "at" => "2026-02-26T10:00:05Z"},
            %{"step" => "complete", "at" => "2026-02-26T10:00:06Z"}
          ]
        }
      }

      timeline = Archiving.merge_timeline(archive_steps, [snapshot1, snapshot2])

      step_names = Enum.map(timeline, & &1["step"])
      prefixes = Enum.map(timeline, & &1["prefix"])

      # singlefile group (t=02) sorts before wayback group (t=05),
      # both after dispatched (t=01) and before complete (t=20)
      assert step_names == [
               "created",
               "dispatched",
               "crawling",
               "stored",
               "crawling",
               "complete",
               "complete"
             ]

      assert prefixes == [nil, nil, "singlefile", "singlefile", "wayback", "wayback", nil]

      # Archive steps have no group
      refute Enum.at(timeline, 0)["group"]
      refute Enum.at(timeline, 1)["group"]
      refute Enum.at(timeline, 6)["group"]

      # singlefile is group 1, wayback is group 2
      assert Enum.at(timeline, 2)["group"] == 1
      assert Enum.at(timeline, 3)["group"] == 1
      assert Enum.at(timeline, 4)["group"] == 2
      assert Enum.at(timeline, 5)["group"] == 2
    end
  end

  describe "maybe_complete_archive/1" do
    test "transitions processing archive to complete when all snapshots are terminal" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          archive_id: archive.id
        })

      Archiving.maybe_complete_archive(archive.id)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :complete
      assert Enum.any?(updated.steps, &(&1["step"] == "completed"))
    end

    test "does not transition when non-terminal snapshots remain" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :crawling,
          archive_id: archive.id
        })

      Archiving.maybe_complete_archive(archive.id)

      assert Repo.get(Archive, archive.id).state == :processing
    end

    test "is a no-op for non-processing archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :failed
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

      assert :ok = Archiving.maybe_complete_archive(archive.id)
      assert Repo.get(Archive, archive.id).state == :failed
    end

    test "does not complete archive with zero snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      Archiving.maybe_complete_archive(archive.id)

      assert Repo.get(Archive, archive.id).state == :processing
    end

    test "handles nil archive_id" do
      assert :ok = Archiving.maybe_complete_archive(nil)
    end

    test "only one concurrent caller wins the transition (race safety)" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          archive_id: archive.id
        })

      # Call twice — only one should add the "completed" step
      Archiving.maybe_complete_archive(archive.id)
      Archiving.maybe_complete_archive(archive.id)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :complete

      completed_steps = Enum.filter(updated.steps, &(&1["step"] == "completed"))
      assert length(completed_steps) == 1
    end
  end

  describe "schedule_recrawl/1" do
    test "enqueues archiver job scheduled in the future" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, _job} = Archiving.schedule_recrawl(link)

      alias Linkhut.Archiving.Workers.Archiver
      [job] = all_enqueued(worker: Archiver)
      assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
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

    test "excludes links with any archive or snapshot activity" do
      user = insert(:user, credential: build(:credential))

      # Link with a processing archive
      link_processing = insert(:link, user_id: user.id)
      _archive = create_archive(user, link_processing)

      # Link with a complete archive
      link_complete = insert(:link, user_id: user.id)

      insert(:archive,
        user_id: user.id,
        link_id: link_complete.id,
        url: link_complete.url,
        state: :complete
      )

      # Link with a failed archive
      link_failed = insert(:link, user_id: user.id)

      insert(:archive,
        user_id: user.id,
        link_id: link_failed.id,
        url: link_failed.url,
        state: :failed
      )

      # Link with a pending archive
      link_pending = insert(:link, user_id: user.id)

      insert(:archive,
        user_id: user.id,
        link_id: link_pending.id,
        url: link_pending.url,
        state: :pending
      )

      result = Archiving.list_unarchived_links_for_user(user)
      returned_ids = Enum.map(result, & &1.id)
      refute link_processing.id in returned_ids
      refute link_complete.id in returned_ids
      refute link_failed.id in returned_ids
      refute link_pending.id in returned_ids
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

    test "orders by inserted_at descending (newest first)" do
      user = insert(:user, credential: build(:credential))
      now = NaiveDateTime.utc_now()
      link1 = insert(:link, user_id: user.id, inserted_at: NaiveDateTime.add(now, -60))
      link2 = insert(:link, user_id: user.id, inserted_at: now)

      result = Archiving.list_unarchived_links_for_user(user)
      assert [first, second] = result
      assert first.id == link2.id
      assert second.id == link1.id
    end
  end
end
