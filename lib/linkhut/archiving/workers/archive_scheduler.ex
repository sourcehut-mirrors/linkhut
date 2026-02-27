defmodule Linkhut.Archiving.Workers.ArchiveScheduler do
  @moduledoc """
  Periodic worker that schedules archive jobs for active paying users.
  Runs daily via Oban cron to find unarchived links and queue them for processing.
  """

  use Oban.Worker, queue: :default, unique: [period: {15, :minute}]

  alias Linkhut.Archiving.Scheduler

  @impl Oban.Worker
  def perform(_job) do
    case Linkhut.Archiving.mode() do
      :disabled ->
        :ok

      _ ->
        jobs = Scheduler.schedule_pending_archives()
        {:ok, %{scheduled_jobs: length(jobs), timestamp: DateTime.utc_now()}}
    end
  end
end
