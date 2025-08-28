defmodule Linkhut.Archiving.Scheduler do
  @moduledoc "Manages fair distribution of archive jobs across users and domains"

  alias Linkhut.{Accounts, Links}

  @doc """
  Schedules pending archives for all active paying users.
  Returns a list of scheduled job results.
  """
  def schedule_pending_archives do
    Accounts.list_active_paying_users()
    |> distribute_archive_jobs()
  end

  defp distribute_archive_jobs(users) do
    # Round-robin through users to ensure fairness
    users
    |> Enum.with_index()
    |> Enum.flat_map(fn {user, index} ->
      # Stagger job scheduling to prevent domain flooding
      # 30 second intervals
      delay_seconds = index * 30
      schedule_user_archives(user, delay_seconds)
    end)
  end

  defp schedule_user_archives(user, delay_seconds) do
    # Limit per user per run
    Links.list_unarchived_links_for_user(user, 10)
    |> group_by_domain()
    |> Enum.flat_map(fn {_domain, links} ->
      # Space out same-domain requests by 60 seconds
      links
      |> Enum.with_index()
      |> Enum.map(fn {link, domain_index} ->
        total_delay = delay_seconds + domain_index * 60
        schedule_archive_job(link, total_delay)
      end)
    end)
  end

  defp group_by_domain(links) do
    Enum.group_by(links, fn link ->
      URI.parse(link.url).host || "unknown"
    end)
  end

  defp schedule_archive_job(link, delay_seconds) do
    Linkhut.Workers.Archiver.enqueue(link, schedule_in: delay_seconds)
  end
end
