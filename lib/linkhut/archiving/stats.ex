defmodule Linkhut.Archiving.Stats do
  @moduledoc "Statistics relating to snapshots."

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Archiving
  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Repo

  @doc "Returns archive statistics for a user."
  def archive_stats_for_user(%User{} = user) do
    breakdown = snapshot_breakdown(user.id)

    %{
      archived_links: archived_links(user.id),
      total_snapshots: breakdown |> Enum.map(& &1.total_count) |> Enum.sum(),
      snapshot_breakdown: breakdown,
      total_storage_bytes: breakdown |> Enum.map(& &1.total_size) |> Enum.sum()
    }
  end

  defp archived_links(user_id) do
    Snapshot
    |> where(user_id: ^user_id, state: :complete)
    |> select([s], count(s.link_id, :distinct))
    |> Repo.one()
  end

  @doc "Returns the archiving mode and the total storage used."
  def admin_archive_stats do
    %{mode: Archiving.mode(), total_storage_bytes: storage_used()}
  end

  defp snapshot_breakdown(user_id) do
    Snapshot
    |> where(user_id: ^user_id)
    |> group_by([s], [s.format, s.state])
    |> select([s], %{
      format: s.format,
      state: s.state,
      count: count(s.id),
      size: coalesce(sum(s.file_size_bytes), 0)
    })
    |> order_by([s], [s.format, s.state])
    |> Repo.all()
    |> Enum.map(fn row -> %{row | size: to_integer(row.size)} end)
    |> Enum.group_by(& &1.format)
    |> Enum.sort_by(fn {format, _} -> format end)
    |> Enum.map(fn {format, rows} ->
      %{
        format: format,
        states: Enum.map(rows, &{&1.state, &1.count, &1.size}),
        total_count: rows |> Enum.map(& &1.count) |> Enum.sum(),
        total_size: rows |> Enum.map(& &1.size) |> Enum.sum()
      }
    end)
  end

  @doc "Returns total storage across all users."
  def storage_used do
    Snapshot
    |> where(state: :complete)
    |> Repo.aggregate(:sum, :file_size_bytes)
    |> to_integer()
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n
end
