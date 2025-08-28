defmodule Linkhut.Archiving do
  @moduledoc """
  Manages link archiving — creating snapshots of bookmarked pages,
  storing them, and generating time-limited tokens to view them.

  Crawling is handled by `Linkhut.Workers.Archiver` and `Linkhut.Workers.Crawler`,
  which call back into this context to persist results.
  """

  alias Linkhut.Archiving.{Snapshot, Tokens}
  alias Linkhut.Repo

  def generate_token(snapshot_id), do: Tokens.generate_token(snapshot_id)
  def verify_token(token), do: Tokens.verify_token(token)

  def get_complete_snapshot(id) do
    case Repo.get(Snapshot, id) do
      %Snapshot{state: :complete} = snapshot -> {:ok, snapshot}
      _ -> {:error, :not_found}
    end
  end

  def create_snapshot(link_id, job_id, attrs \\ %{}) do
    %Snapshot{link_id: link_id, job_id: job_id}
    |> Snapshot.changeset(attrs)
    |> Repo.insert()
  end

  def get_snapshot(link_id, job_id) do
    Snapshot
    |> Repo.get_by(link_id: link_id, job_id: job_id)
  end

  def update_snapshot(%Snapshot{} = snapshot, attrs) do
    snapshot
    |> Snapshot.changeset(attrs)
    |> Repo.update()
  end
end
