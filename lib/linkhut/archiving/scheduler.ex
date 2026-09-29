defmodule Linkhut.Archiving.Scheduler do
  @moduledoc """
  Queue-filler scheduler: keeps the archiver queue full with user-fair
  interleaving and domain-polite cooldown skipping.

  Runs every 2 minutes via `ArchiveScheduler`, checks available archiver
  queue capacity, and fills slots immediately. Domain politeness is achieved
  by skipping domains on cooldown (not delaying), and user fairness by
  round-robin interleaving and shuffling the user list.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Archiving
  alias Linkhut.Archiving.LinkArchival
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  require Logger

  @domain_cooldown_seconds 120

  @doc """
  Schedules pending archives for eligible users based on the archiving mode.
  Returns a list of scheduled job results, or an empty list when disabled
  or when no work is available.
  """
  def schedule_pending_archives do
    case Archiving.eligible_users() do
      [] -> []
      users -> fill_queue(users)
    end
  end

  defp fill_queue(users) do
    available_slots = available_archiver_slots()

    if available_slots <= 0 do
      Logger.debug("Archive queues full, skipping scheduling")
      []
    else
      schedule_candidates(users, available_slots)
    end
  end

  defp schedule_candidates(users, available_slots) do
    cooldown_domains = domains_on_cooldown()
    candidates_per_user = available_slots * 3

    users
    |> Enum.shuffle()
    |> Enum.map(fn user ->
      list_due_links(user, candidates_per_user)
      |> Enum.reject(&MapSet.member?(cooldown_domains, String.downcase(&1.metadata.host || "")))
    end)
    |> interleave()
    |> Enum.take(available_slots)
    |> Enum.map(&enqueue/1)
  end

  @doc false
  def interleave(lists) do
    do_interleave(lists, [])
  end

  defp do_interleave(lists, acc) do
    case Enum.reject(lists, &(&1 == [])) do
      [] ->
        Enum.reverse(acc)

      non_empty ->
        heads = Enum.map(non_empty, &hd/1)
        tails = Enum.map(non_empty, &tl/1)
        do_interleave(tails, Enum.reverse(heads) ++ acc)
    end
  end

  defp enqueue(link) do
    Linkhut.Archiving.Workers.Archiver.enqueue(link)
  end

  @doc "Lists a user's links that are due for archiving, newest first."
  def list_due_links(%User{} = user, limit \\ 50) do
    crawlers = Linkhut.Config.archiving(:crawlers, [])

    from(l in Link,
      as: :link,
      where: l.user_id == ^user.id,
      where: ^LinkArchival.due(crawlers),
      order_by: [desc: l.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp domains_on_cooldown do
    cutoff = DateTime.add(DateTime.utc_now(), -@domain_cooldown_seconds)

    from(a in LinkArchival,
      join: l in Link,
      on: l.id == a.link_id,
      where: a.updated_at > ^cutoff,
      where: not is_nil(fragment("?->>'host'", l.metadata)),
      distinct: true,
      select: fragment("lower(?->>'host')", l.metadata)
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp available_archiver_slots do
    queue_limit = archiver_queue_limit()

    active =
      from(j in Oban.Job,
        where: j.queue == "archiver",
        where: j.state in ["available", "scheduled", "executing", "retryable"],
        select: count(j.id)
      )
      |> Repo.one()

    max(queue_limit - active, 0)
  end

  defp archiver_queue_limit do
    case Application.get_env(:linkhut, Oban)[:queues] do
      queues when is_list(queues) -> Keyword.get(queues, :archiver, 5)
      _ -> 5
    end
  end
end
