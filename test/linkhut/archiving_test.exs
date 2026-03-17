defmodule Linkhut.ArchivingTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{CrawlRun, Snapshot}

  defp create_crawl_run(user, link) do
    insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url)
  end

  describe "can_create_archives?/1" do
    test "returns false for all users when disabled" do
      put_override(Linkhut.Archiving, :mode, :disabled)

      user = insert(:user, type: :active)
      assert Archiving.can_create_archives?(user) == false

      free_user = insert(:user, type: :active)
      assert Archiving.can_create_archives?(free_user) == false
    end

    test "returns true for all active users when enabled" do
      put_override(Linkhut.Archiving, :mode, :enabled)

      user = insert(:user, type: :active)
      assert Archiving.can_create_archives?(user) == true

      free_user = insert(:user, type: :active)
      assert Archiving.can_create_archives?(free_user) == true
    end

    test "returns true only for users with active supporter subscription when limited" do
      put_override(Linkhut.Archiving, :mode, :limited)

      user_with_sub = insert(:user, type: :active)
      insert(:subscription, user_id: user_with_sub.id, plan: :supporter, status: :active)
      assert Archiving.can_create_archives?(user_with_sub) == true

      user_without_sub = insert(:user, type: :active)
      assert Archiving.can_create_archives?(user_without_sub) == false
    end

    test "returns false for non-active users regardless of mode" do
      put_override(Linkhut.Archiving, :mode, :enabled)

      assert Archiving.can_create_archives?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
      assert Archiving.can_create_archives?(nil) == false
    end
  end

  describe "can_view_archives?/1" do
    test "returns false for all users when disabled" do
      put_override(Linkhut.Archiving, :mode, :disabled)

      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == false
      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == false
    end

    test "returns true for all active users when enabled" do
      put_override(Linkhut.Archiving, :mode, :enabled)

      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == true
      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == true
    end

    test "returns true for all active users when limited" do
      put_override(Linkhut.Archiving, :mode, :limited)

      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == true
      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :active}) == true
    end

    test "returns false for non-active users regardless of mode" do
      put_override(Linkhut.Archiving, :mode, :enabled)

      assert Archiving.can_view_archives?(%Linkhut.Accounts.User{type: :unconfirmed}) == false
      assert Archiving.can_view_archives?(nil) == false
    end
  end

  describe "create_crawl_run/1" do
    test "creates archive with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %CrawlRun{} = crawl_run} =
               Archiving.create_crawl_run(%{
                 link_id: link.id,
                 user_id: user.id,
                 url: link.url,
                 state: :pending
               })

      assert crawl_run.link_id == link.id
      assert crawl_run.user_id == user.id
      assert crawl_run.url == link.url
      assert crawl_run.state == :pending
    end
  end

  describe "start_processing/1" do
    test "transitions pending archive to processing" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :pending
        )

      assert {:ok, processing} = Archiving.start_processing(crawl_run.id)
      assert processing.state == :processing
    end

    test "is idempotent for already-processing archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      assert {:ok, same} = Archiving.start_processing(crawl_run.id)
      assert same.id == crawl_run.id
      assert same.state == :processing
    end

    test "returns error for non-existent archive" do
      assert {:error, :not_found} = Archiving.start_processing(999_999)
    end

    test "returns error for failed archive" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :failed
        )

      assert {:error, :not_found} = Archiving.start_processing(crawl_run.id)
    end
  end

  describe "mark_old_crawl_runs_for_deletion/2" do
    test "marks archives in all states for deletion, excluding specified IDs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      processing_crawl_run = create_crawl_run(user, link)

      complete_crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :complete)

      failed_crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :failed)

      pending_crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :pending)

      excluded_crawl_run = create_crawl_run(user, link)

      :ok = Archiving.mark_old_crawl_runs_for_deletion(link.id, exclude: [excluded_crawl_run.id])

      assert Repo.get(CrawlRun, processing_crawl_run.id).state == :pending_deletion
      assert Repo.get(CrawlRun, complete_crawl_run.id).state == :pending_deletion
      assert Repo.get(CrawlRun, failed_crawl_run.id).state == :pending_deletion
      assert Repo.get(CrawlRun, pending_crawl_run.id).state == :pending_deletion
      assert Repo.get(CrawlRun, excluded_crawl_run.id).state == :processing
    end
  end

  describe "create_snapshot/3" do
    test "creates a snapshot with required fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      assert {:ok, %Snapshot{} = snapshot} =
               Archiving.create_snapshot(link.id, user.id, %{crawl_run_id: crawl_run.id})

      assert snapshot.link_id == link.id
      assert snapshot.user_id == user.id
      assert snapshot.crawl_run_id == crawl_run.id
    end

    test "creates a snapshot with all fields" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      attrs = %{
        crawl_run_id: crawl_run.id,
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

    test "rejects snapshot without crawl_run_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:error, changeset} = Archiving.create_snapshot(link.id, user.id)
      assert %{crawl_run_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_snapshot/2" do
    test "returns snapshot by link_id and job_id" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      # Create a real Oban job to satisfy the FK constraint
      {:ok, oban_job} =
        Linkhut.Archiving.Workers.Archiver.new(%{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => link.url,
          "crawl_run_id" => crawl_run.id
        })
        |> Oban.insert()

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          crawl_run_id: crawl_run.id,
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
      crawl_run = create_crawl_run(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{crawl_run_id: crawl_run.id})

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
      crawl_run = create_crawl_run(user, link)

      {:ok, s1} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending,
          crawl_run_id: crawl_run.id
        })

      assert :ok = Archiving.mark_snapshots_for_deletion(link.id)

      assert Repo.get(Snapshot, s1.id).state == :pending_deletion
      assert Repo.get(Snapshot, s2.id).state == :pending_deletion
    end

    test "does not affect snapshots for other links" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)
      crawl_run1 = create_crawl_run(user, link1)
      crawl_run2 = create_crawl_run(user, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run1.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link2.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run2.id
        })

      Archiving.mark_snapshots_for_deletion(link1.id)

      assert Repo.get(Snapshot, s2.id).state == :complete
    end
  end

  describe "enqueue_pending_deletions/0" do
    test "enqueues a SnapshotDeleter job for each pending_deletion snapshot" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, s1} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          crawl_run_id: crawl_run.id
        })

      {:ok, s2} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          crawl_run_id: crawl_run.id
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
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
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
      crawl_run = create_crawl_run(user, link)

      path = Path.join(@data_dir, "1/100/10/42.singlefile")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "content")

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          storage_key: "local:" <> path,
          crawl_run_id: crawl_run.id
        })

      assert :ok = Archiving.delete_snapshot(snapshot.id)

      assert Repo.get(Snapshot, snapshot.id) == nil
      refute File.exists?(path)
    end

    test "deletes record when storage_key is nil" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          crawl_run_id: crawl_run.id
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
      crawl_run = create_crawl_run(user, link)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :pending_deletion,
          storage_key: "cloud:bucket/key",
          crawl_run_id: crawl_run.id
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
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          file_size_bytes: 500,
          crawl_run_id: crawl_run.id
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
      crawl_run1 = create_crawl_run(user1, link1)
      crawl_run2 = create_crawl_run(user2, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user1.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run1.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user2.id, %{
          state: :complete,
          file_size_bytes: 2000,
          crawl_run_id: crawl_run2.id
        })

      assert Archiving.storage_used_by_user(user1.id) == 1000
    end

    test "returns 0 for user with no snapshots" do
      user = insert(:user, credential: build(:credential))
      assert Archiving.storage_used_by_user(user.id) == 0
    end
  end

  describe "recompute_crawl_run_size/1" do
    test "sums only complete snapshots for an archive" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          file_size_bytes: 500,
          crawl_run_id: crawl_run.id
        })

      Archiving.recompute_crawl_run_size(crawl_run)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.total_size_bytes == 3000
    end
  end

  describe "recompute_crawl_run_size_by_id/1" do
    test "returns :ok for nil" do
      assert :ok = Archiving.recompute_crawl_run_size_by_id(nil)
    end

    test "returns :ok for non-existent archive ID" do
      assert :ok = Archiving.recompute_crawl_run_size_by_id(999_999)
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

  describe "maybe_complete_crawl_run/1" do
    test "transitions processing archive to complete when all snapshots are terminal" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :failed,
          crawl_run_id: crawl_run.id
        })

      Archiving.maybe_complete_crawl_run(crawl_run.id)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :complete
      assert Enum.any?(updated.steps, &(&1["step"] == "completed"))
    end

    test "does not transition when non-terminal snapshots remain" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :crawling,
          crawl_run_id: crawl_run.id
        })

      Archiving.maybe_complete_crawl_run(crawl_run.id)

      assert Repo.get(CrawlRun, crawl_run.id).state == :processing
    end

    test "is a no-op for non-processing archives" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :failed
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
        })

      assert :ok = Archiving.maybe_complete_crawl_run(crawl_run.id)
      assert Repo.get(CrawlRun, crawl_run.id).state == :failed
    end

    test "does not complete archive with zero snapshots" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      Archiving.maybe_complete_crawl_run(crawl_run.id)

      assert Repo.get(CrawlRun, crawl_run.id).state == :processing
    end

    test "handles nil crawl_run_id" do
      assert :ok = Archiving.maybe_complete_crawl_run(nil)
    end

    test "only one concurrent caller wins the transition (race safety)" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          user_id: user.id,
          link_id: link.id,
          url: link.url,
          state: :processing
        )

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          crawl_run_id: crawl_run.id
        })

      # Call twice — only one should add the "completed" step
      Archiving.maybe_complete_crawl_run(crawl_run.id)
      Archiving.maybe_complete_crawl_run(crawl_run.id)

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :complete

      completed_steps = Enum.filter(updated.steps, &(&1["step"] == "completed"))
      assert length(completed_steps) == 1
    end
  end

  describe "archive_stats_for_user/1" do
    test "returns zeroes for user with no links" do
      user = insert(:user, credential: build(:credential))
      stats = Archiving.archive_stats_for_user(user)

      assert stats.archived_links == 0
      assert stats.pending_links == 0
      assert stats.total_storage_bytes == 0
      assert stats.snapshots_by_type == []
    end

    test "counts links and archived links correctly" do
      user = insert(:user, credential: build(:credential))
      link1 = insert(:link, user_id: user.id)
      link2 = insert(:link, user_id: user.id)
      _link3 = insert(:link, user_id: user.id)
      crawl_run1 = create_crawl_run(user, link1)
      crawl_run2 = create_crawl_run(user, link2)

      {:ok, _} =
        Archiving.create_snapshot(link1.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run1.id,
          type: "singlefile"
        })

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user.id, %{
          state: :complete,
          file_size_bytes: 2000,
          crawl_run_id: crawl_run2.id,
          type: "singlefile"
        })

      stats = Archiving.archive_stats_for_user(user)

      assert stats.archived_links == 2
      assert stats.total_storage_bytes == 3000
    end

    test "counts pending links" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      insert(:crawl_run,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :pending
      )

      stats = Archiving.archive_stats_for_user(user)
      assert stats.pending_links == 1
    end

    test "groups snapshots by type" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run.id,
          type: "singlefile"
        })

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 500,
          crawl_run_id: crawl_run.id,
          type: "wayback"
        })

      stats = Archiving.archive_stats_for_user(user)

      assert length(stats.snapshots_by_type) == 2

      sf = Enum.find(stats.snapshots_by_type, &(&1.type == "singlefile"))
      assert sf.count == 1
      assert sf.size == 1000

      wb = Enum.find(stats.snapshots_by_type, &(&1.type == "wayback"))
      assert wb.count == 1
      assert wb.size == 500
    end

    test "does not count other users' data" do
      user1 = insert(:user, credential: build(:credential))
      user2 = insert(:user, credential: build(:credential))
      insert(:link, user_id: user1.id)
      link2 = insert(:link, user_id: user2.id)
      crawl_run2 = create_crawl_run(user2, link2)

      {:ok, _} =
        Archiving.create_snapshot(link2.id, user2.id, %{
          state: :complete,
          file_size_bytes: 5000,
          crawl_run_id: crawl_run2.id,
          type: "singlefile"
        })

      stats = Archiving.archive_stats_for_user(user1)

      assert stats.archived_links == 0
      assert stats.total_storage_bytes == 0
    end
  end

  describe "admin_archive_stats/0" do
    test "returns all stat keys" do
      stats = Archiving.admin_archive_stats()

      assert Map.has_key?(stats, :mode)
      assert Map.has_key?(stats, :total_storage_bytes)
      assert Map.has_key?(stats, :archives_by_state)
      assert Map.has_key?(stats, :snapshots_by_state)
      assert Map.has_key?(stats, :snapshots_by_type)
      assert Map.has_key?(stats, :queue_depths)
      assert Map.has_key?(stats, :recent_failures)
      assert Map.has_key?(stats, :top_users)
      assert Map.has_key?(stats, :stale_work)
    end

    test "includes archive and snapshot state counts" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 1000,
          crawl_run_id: crawl_run.id,
          type: "singlefile"
        })

      stats = Archiving.admin_archive_stats()

      assert Enum.any?(stats.archives_by_state, fn {state, count} ->
               state == :processing and count >= 1
             end)

      assert Enum.any?(stats.snapshots_by_state, fn {state, count} ->
               state == :complete and count >= 1
             end)
    end

    test "includes top users by storage" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)
      crawl_run = create_crawl_run(user, link)

      {:ok, _} =
        Archiving.create_snapshot(link.id, user.id, %{
          state: :complete,
          file_size_bytes: 5000,
          crawl_run_id: crawl_run.id,
          type: "singlefile"
        })

      stats = Archiving.admin_archive_stats()
      assert Enum.any?(stats.top_users, &(&1.username == user.username))
    end

    test "stale_work returns counts" do
      stats = Archiving.admin_archive_stats()
      assert stats.stale_work.stale_archives == 0
      assert stats.stale_work.stale_snapshots == 0
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
      _crawl_run = create_crawl_run(user, link_processing)

      # Link with a complete archive
      link_complete = insert(:link, user_id: user.id)

      insert(:crawl_run,
        user_id: user.id,
        link_id: link_complete.id,
        url: link_complete.url,
        state: :complete
      )

      # Link with a failed archive
      link_failed = insert(:link, user_id: user.id)

      insert(:crawl_run,
        user_id: user.id,
        link_id: link_failed.id,
        url: link_failed.url,
        state: :failed
      )

      # Link with a pending archive
      link_pending = insert(:link, user_id: user.id)

      insert(:crawl_run,
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
