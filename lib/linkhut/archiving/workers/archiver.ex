defmodule Linkhut.Archiving.Workers.Archiver do
  @moduledoc """
  Validates a link's URL (SSRF checks, redirect following) and dispatches
  per-crawler jobs via `Linkhut.Archiving.Workers.Crawler`.

  This worker is intentionally thin — orchestration logic lives in
  `Linkhut.Archiving.Pipeline` for unit-testability.
  """

  use Oban.Worker,
    queue: :default,
    # Initial attempt + 3 retries
    max_attempts: 4,
    unique: [
      period: {1, :hour},
      keys: [:link_id, :recrawl],
      states: :all
    ]

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Pipeline

  def enqueue(link, opts \\ []) do
    args =
      %{user_id: link.user_id, link_id: link.id, url: link.url}
      |> maybe_add_recrawl(opts)

    args
    |> __MODULE__.new(Keyword.delete(opts, :recrawl))
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"user_id" => user_id, "link_id" => link_id, "url" => url} = args
        } = job
      ) do
    recrawl = Map.get(args, "recrawl", false)

    with {:ok, archive} <- Archiving.get_or_create_archive(job.id, link_id, user_id, url) do
      Pipeline.run(archive,
        recrawl: recrawl,
        attempt: job.attempt,
        max_attempts: job.max_attempts
      )
    end
  end

  defp maybe_add_recrawl(args, opts) do
    if Keyword.get(opts, :recrawl, false) do
      Map.put(args, :recrawl, true)
    else
      args
    end
  end
end
