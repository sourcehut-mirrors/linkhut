defmodule Linkhut.Archiving.SchedulerTest do
  use Linkhut.DataCase, async: true

  import Linkhut.Factory

  alias Linkhut.Archiving.Scheduler

  describe "schedule_pending_archives/0" do
    test "returns empty list when archiving is disabled" do
      put_override(Linkhut.Archiving, :mode, :disabled)

      user = insert(:user, credential: build(:credential), type: :active_paying)
      insert(:link, user_id: user.id)

      assert [] = Scheduler.schedule_pending_archives()
    end

    test "returns empty list when no paying users exist" do
      assert [] = Scheduler.schedule_pending_archives()
    end

    test "schedules jobs for unarchived links of paying users" do
      user = insert(:user, credential: build(:credential), type: :active_paying)
      insert(:link, user_id: user.id)

      results = Scheduler.schedule_pending_archives()
      assert results != []
    end

    test "does not schedule jobs for links that already have snapshots" do
      user = insert(:user, credential: build(:credential), type: :active_paying)
      link = insert(:link, user_id: user.id)

      insert(:snapshot, link_id: link.id, user_id: user.id, state: :complete)

      results = Scheduler.schedule_pending_archives()
      assert results == []
    end

    test "does not schedule jobs for links with processing archives" do
      user = insert(:user, credential: build(:credential), type: :active_paying)
      link = insert(:link, user_id: user.id)

      insert(:archive, link_id: link.id, user_id: user.id, url: link.url, state: :processing)

      results = Scheduler.schedule_pending_archives()
      assert results == []
    end
  end
end
