defmodule Linkhut.Archiving.Scheduler do
  @moduledoc """
  Queue-filler scheduler: keeps the archiver queue full with user-fair
  interleaving and domain-polite cooldown skipping.

  Runs every 2 minutes via `ArchiveScheduler`, checks available archiver
  queue capacity, and fills slots immediately. Domain politeness is achieved
  by skipping domains on cooldown (not delaying), and user fairness by
  round-robin interleaving and shuffling the user list.
  """

  alias Linkhut.Archiving
  require Logger

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
    available_slots = Archiving.available_archiver_slots()

    if available_slots <= 0 do
      Logger.debug("Archive queues full, skipping scheduling")
      []
    else
      schedule_candidates(users, available_slots)
    end
  end

  defp schedule_candidates(users, available_slots) do
    cooldown_domains = Archiving.domains_on_cooldown()
    candidates_per_user = available_slots * 3

    users
    |> Enum.shuffle()
    |> Enum.map(fn user ->
      Archiving.list_unarchived_links_for_user(user, candidates_per_user)
      |> Enum.reject(fn link ->
        MapSet.member?(cooldown_domains, Archiving.extract_domain(link.url))
      end)
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
end
