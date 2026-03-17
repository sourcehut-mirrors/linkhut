defmodule Linkhut.Archiving.SchedulerTest do
  use Linkhut.DataCase, async: true

  import Linkhut.Factory

  alias Linkhut.Archiving.Scheduler

  defp create_paying_user do
    user = insert(:user, credential: build(:credential), type: :active)
    insert(:subscription, user_id: user.id, plan: :supporter, status: :active)
    user
  end

  describe "schedule_pending_archives/0" do
    test "returns empty list when archiving is disabled" do
      put_override(Linkhut.Archiving, :mode, :disabled)

      user = create_paying_user()
      insert(:link, user_id: user.id)

      assert [] = Scheduler.schedule_pending_archives()
    end

    test "returns empty list when no eligible users exist" do
      assert [] = Scheduler.schedule_pending_archives()
    end

    test "schedules jobs for unarchived links" do
      user = create_paying_user()
      insert(:link, user_id: user.id)

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 1
    end

    test "in limited mode, only schedules for users with active supporter subscription" do
      put_override(Linkhut.Archiving, :mode, :limited)

      subscribed_user = create_paying_user()
      insert(:link, user_id: subscribed_user.id)

      free_user = insert(:user, credential: build(:credential), type: :active)
      insert(:link, user_id: free_user.id)

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 1
    end

    test "does not schedule jobs for links that already have snapshots" do
      user = create_paying_user()
      link = insert(:link, user_id: user.id)

      insert(:snapshot, link_id: link.id, user_id: user.id, state: :complete)

      assert [] = Scheduler.schedule_pending_archives()
    end

    test "does not schedule jobs for links with active archives" do
      user = create_paying_user()
      link = insert(:link, user_id: user.id)

      insert(:crawl_run, link_id: link.id, user_id: user.id, url: link.url, state: :processing)

      assert [] = Scheduler.schedule_pending_archives()
    end

    test "skips links whose domain is on cooldown" do
      user = create_paying_user()

      # Create a link on example.com
      link = insert(:link, user_id: user.id, url: "http://example.com/page1")

      # Create a recent archive for another URL on the same domain
      # (this puts example.com on cooldown)
      insert(:crawl_run,
        user_id: user.id,
        url: "http://example.com/other-page",
        state: :complete
      )

      assert [] = Scheduler.schedule_pending_archives()

      # But a link on a different domain should still be scheduled
      insert(:link, user_id: user.id, url: "http://other-domain.com/page")

      results = Scheduler.schedule_pending_archives()
      # Should schedule other-domain.com but not example.com
      assert length(results) == 1

      # Verify the example.com link was skipped (it's still unarchived)
      assert Linkhut.Archiving.list_unarchived_links_for_user(user, 50)
             |> Enum.any?(&(&1.id == link.id))
    end

    test "schedules links on different domains even when one domain is on cooldown" do
      user = create_paying_user()

      insert(:link, user_id: user.id, url: "http://cooldown-domain.com/page")
      insert(:link, user_id: user.id, url: "http://available-domain.com/page")

      # Put cooldown-domain.com on cooldown
      insert(:crawl_run,
        user_id: user.id,
        url: "http://cooldown-domain.com/other",
        state: :pending
      )

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 1
    end

    test "interleaves across multiple users" do
      user1 = create_paying_user()
      user2 = create_paying_user()

      insert(:link, user_id: user1.id, url: "http://a.com/1")
      insert(:link, user_id: user1.id, url: "http://b.com/1")
      insert(:link, user_id: user2.id, url: "http://c.com/1")
      insert(:link, user_id: user2.id, url: "http://d.com/1")

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 4
    end

    test "respects available queue capacity" do
      # In test mode, Oban config has no queues key, so archiver_queue_limit
      # defaults to 5. We insert 10 links but should only get up to 5.
      user = create_paying_user()

      for i <- 1..10 do
        insert(:link, user_id: user.id, url: "http://domain-#{i}.com/page")
      end

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 5
    end

    test "returns empty list when all candidate domains are on cooldown" do
      user = create_paying_user()

      insert(:link, user_id: user.id, url: "http://cooldown1.com/page")
      insert(:link, user_id: user.id, url: "http://cooldown2.com/page")

      # Put both domains on cooldown
      insert(:crawl_run, user_id: user.id, url: "http://cooldown1.com/other", state: :pending)
      insert(:crawl_run, user_id: user.id, url: "http://cooldown2.com/other", state: :pending)

      assert [] = Scheduler.schedule_pending_archives()
    end
  end

  describe "interleave/1" do
    test "interleaves equal-length lists" do
      result = Scheduler.interleave([[1, 2], [3, 4]])
      assert result == [1, 3, 2, 4]
    end

    test "interleaves uneven lists" do
      result = Scheduler.interleave([[1, 2, 3], [4]])
      assert result == [1, 4, 2, 3]
    end

    test "handles empty lists" do
      assert Scheduler.interleave([]) == []
      assert Scheduler.interleave([[], []]) == []
    end

    test "handles single list" do
      assert Scheduler.interleave([[1, 2, 3]]) == [1, 2, 3]
    end

    test "handles mix of empty and non-empty lists" do
      result = Scheduler.interleave([[1, 2], [], [3, 4]])
      assert result == [1, 3, 2, 4]
    end
  end
end
