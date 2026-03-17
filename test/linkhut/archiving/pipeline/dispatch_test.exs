defmodule Linkhut.Archiving.Pipeline.DispatchTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Snapshot, Pipeline.Dispatch}

  describe "dispatch_crawlers/3" do
    test "creates snapshots and enqueues jobs atomically" do
      {_user, _link, crawl_run} = create_crawl_run()
      crawlers = [Linkhut.Archiving.Crawler.SingleFile]

      assert {:ok, result} = Dispatch.dispatch_crawlers(crawl_run, crawlers, [])
      assert %{crawlers: dispatched} = result
      assert length(dispatched) == 1
      assert hd(dispatched).name == "singlefile"

      snapshots = Repo.all(from s in Snapshot, where: s.crawl_run_id == ^crawl_run.id)
      assert length(snapshots) == 1
      assert hd(snapshots).state == :pending
    end

    test "passes recrawl flag to job args" do
      {_user, _link, crawl_run} = create_crawl_run()
      crawlers = [Linkhut.Archiving.Crawler.SingleFile]

      assert {:ok, _} = Dispatch.dispatch_crawlers(crawl_run, crawlers, recrawl: true)

      assert_enqueued(
        worker: Linkhut.Archiving.Workers.Crawler,
        args: %{"recrawl" => true, "crawl_run_id" => crawl_run.id}
      )
    end

    test "raises on empty crawler list" do
      {_user, _link, crawl_run} = create_crawl_run()

      assert_raise ArgumentError, fn ->
        Dispatch.dispatch_crawlers(crawl_run, [], [])
      end
    end
  end

  defp create_crawl_run do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, crawl_run} =
      Archiving.create_crawl_run(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, crawl_run}
  end
end
