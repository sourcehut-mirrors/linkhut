defmodule Linkhut.Archiving.Workers.Reconciler do
  @moduledoc """
  Periodic worker that finds links with uncovered sources (missing crawler
  types compared to current config) and dispatches reconciliation crawl
  runs for only the missing crawlers.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {1, :hour}, states: [:available, :scheduled, :executing, :retryable]]

  alias Linkhut.Archiving

  require Logger

  @max_enqueued 500

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Archiving.eligible_users() do
      [] ->
        Logger.debug("Reconciler: no eligible users, skipping")
        :ok

      users ->
        reconciled = reconcile_users(users, @max_enqueued)
        Logger.info("Reconciler: reconciled #{reconciled} links")
        :ok
    end
  end

  defp reconcile_users(users, budget) do
    Enum.reduce_while(users, 0, fn user, count ->
      enqueued = reconcile_user(user)

      if count + enqueued >= budget do
        {:halt, count + enqueued}
      else
        {:cont, count + enqueued}
      end
    end)
  end

  defp reconcile_user(user) do
    user
    |> Archiving.list_reconcilable_links()
    |> Enum.count(fn {link, remaining} -> enqueue(link, remaining) end)
  end

  defp enqueue(link, remaining_types) do
    types = MapSet.to_list(remaining_types)

    case Archiving.Workers.Archiver.enqueue(link,
           only_types: types,
           reconciliation: true
         ) do
      {:ok, _job} ->
        true

      {:error, reason} ->
        Logger.warning(
          "Reconciler: failed to enqueue link #{link.id}: #{inspect(reason)}"
        )

        false
    end
  end
end
