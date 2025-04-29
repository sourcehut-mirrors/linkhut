defmodule Linkhut.Workers.RefreshViewsWorker do
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [
      period: {2, :minutes},
      timestamp: :scheduled_at
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = _job) do
    Linkhut.Repo.query("refresh materialized view public_links;")
  end
end
