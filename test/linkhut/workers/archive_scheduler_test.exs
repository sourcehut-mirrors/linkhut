defmodule Linkhut.Workers.ArchiveSchedulerTest do
  use Linkhut.DataCase

  alias Linkhut.Workers.ArchiveScheduler

  describe "perform/1" do
    test "returns ok with scheduled jobs count" do
      job = %Oban.Job{id: 1, args: %{}, attempt: 1, max_attempts: 1}

      assert {:ok, %{scheduled_jobs: count, timestamp: %DateTime{}}} =
               ArchiveScheduler.perform(job)

      assert is_integer(count)
    end
  end
end
