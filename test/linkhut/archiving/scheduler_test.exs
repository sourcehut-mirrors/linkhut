defmodule Linkhut.Archiving.SchedulerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.Scheduler

  defp insert_oban_job do
    {:ok, job} =
      Linkhut.Workers.Archiver.new(%{"user_id" => 1, "link_id" => 1, "url" => "https://example.com"})
      |> Oban.insert()

    job
  end

  describe "schedule_pending_archives/0" do
    test "returns empty list when no paying users exist" do
      assert [] = Scheduler.schedule_pending_archives()
    end

    test "schedules jobs for unarchived links of paying users" do
      user = insert(:user, credential: build(:credential), type: :active_paying)
      insert(:link, user_id: user.id)

      results = Scheduler.schedule_pending_archives()
      assert length(results) > 0
    end

    test "does not schedule jobs for links that already have snapshots" do
      user = insert(:user, credential: build(:credential), type: :active_paying)
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()

      insert(:snapshot, link_id: link.id, job_id: job.id, state: :complete)

      results = Scheduler.schedule_pending_archives()
      assert results == []
    end
  end
end
