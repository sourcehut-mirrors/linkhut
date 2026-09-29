defmodule Linkhut.Archiving.SchedulerTest do
  use Linkhut.DataCase, async: true

  import Linkhut.Factory

  alias Linkhut.Archiving.{LinkArchival, Scheduler}

  @archived %{"singlefile" => "1", "httpfetch" => "1", "wayback" => "1"}

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

    test "in limited mode, only schedule archivals for subscribed users" do
      put_override(Linkhut.Archiving, :mode, :limited)

      subscribed_user = create_paying_user()
      insert(:link, user_id: subscribed_user.id)

      free_user = insert(:user, credential: build(:credential), type: :active)
      insert(:link, user_id: free_user.id)

      results = Scheduler.schedule_pending_archives()
      assert length(results) == 1
    end

    test "domain cool down" do
      user = create_paying_user()
      cooling = insert(:link, user_id: user.id, url: "http://cooldown.com/page")
      other = insert(:link, user_id: user.id, url: "http://other-domain.com/page")
      recently_archived(user, "http://CoolDown.com/other")

      assert [{:ok, job}] = Scheduler.schedule_pending_archives()
      assert job.args.link_id == other.id

      Repo.update_all(LinkArchival,
        set: [updated_at: DateTime.add(DateTime.utc_now(:second), -3, :minute)]
      )

      assert [{:ok, job}] = Scheduler.schedule_pending_archives()
      assert job.args.link_id == cooling.id
    end
  end

  describe "interleave/1" do
    test "takes one from each list in turn" do
      assert Scheduler.interleave([[1, 2, 3], [4]]) == [1, 4, 2, 3]
      assert Scheduler.interleave([[1, 2], [], [3, 4]]) == [1, 3, 2, 4]
    end
  end

  describe "list_due_links/2" do
    setup do
      %{user: insert(:user, credential: build(:credential))}
    end

    test "a link every crawler has archived at its version is not due", %{user: user} do
      link = insert(:link, user_id: user.id)
      archived(link, @archived)

      assert due_ids(user) == []
    end

    test "a queued link isn't due", %{user: user} do
      link = insert(:link, user_id: user.id)
      {:ok, _job} = Linkhut.Archiving.Workers.Archiver.enqueue(link)

      assert due_ids(user) == []
    end

    test "a new crawler or a version bump makes a link due", %{user: user} do
      for versions <- [Map.delete(@archived, "httpfetch"), Map.put(@archived, "singlefile", "0")] do
        link = insert(:link, user_id: user.id)
        archived(link, versions)

        assert link.id in due_ids(user), "for #{inspect(versions)}"
      end
    end

    test "only crawlers that apply to a link count", %{user: user} do
      archive = insert(:link, user_id: user.id, url: "https://web.archive.org/web/2020/x")
      archived(archive, Map.delete(@archived, "wayback"))

      assert due_ids(user) == []

      for url <- ["ftp://example.com/file", "gemini://example.com/", "not-a-url"] do
        insert(:link, user_id: user.id, url: url)
      end

      assert due_ids(user) == []
    end
  end

  defp due_ids(user), do: user |> Scheduler.list_due_links() |> Enum.map(& &1.id)

  defp recently_archived(user, url) do
    link = insert(:link, user_id: user.id, url: url)
    archived(link, @archived)
    link
  end

  defp archived(link, versions) do
    for {source, version} <- versions do
      insert(:link_archival, link_id: link.id, source: source, version: version)
    end
  end
end
