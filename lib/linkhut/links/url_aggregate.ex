defmodule Linkhut.Links.UrlAggregate do
  @moduledoc """
  Aggregate queries about a URL's public bookmarks across all users.

  These queries intentionally include unconfirmed users. The URL detail page
  answers "how many people saved this URL?" — the truthful answer includes
  everyone who actually saved it. Unconfirmed users are only excluded from
  discovery views (`recent/2`, `popular/2`) to prevent spam.
  """

  import Ecto.Query

  alias Linkhut.Links.Link
  alias Linkhut.Links.UrlDetail
  alias Linkhut.Repo

  @doc """
  Returns aggregate metadata for a URL's public bookmarks.

  Returns `nil` if no public bookmarks exist for this URL.

  ## Options

    * `:current_user_id` - include the current user's bookmark (even if
      private/unread) in the result
  """
  @spec url_detail(String.t(), keyword()) :: UrlDetail.t() | nil
  def url_detail(url, opts) do
    case summary(url) do
      nil ->
        nil

      summary ->
        granularity = compute_granularity(summary.first_saved_at)

        %UrlDetail{
          url: url,
          title: summary.title,
          total_saves: summary.total_saves,
          first_save: %{username: summary.first_username, saved_at: summary.first_saved_at},
          latest_save: %{username: summary.latest_username, saved_at: summary.latest_saved_at},
          current_user_bookmark: current_user_bookmark(url, opts[:current_user_id]),
          common_tags: common_tags(url),
          domain_saves: domain_saves(url),
          activity: %{
            granularity: granularity,
            buckets: activity_buckets(url, granularity)
          }
        }
    end
  end

  # Fetches count, title, and first/latest save info in a single query
  # using window functions. Returns nil if no public bookmarks exist.
  defp summary(url) do
    from(l in Link,
      join: u in assoc(l, :user),
      where: l.url == ^url,
      where: not l.is_private and not l.is_unread,
      where: not u.is_banned,
      windows: [
        all: [],
        oldest: [order_by: [asc: l.inserted_at]],
        newest: [order_by: [desc: l.inserted_at]]
      ],
      select: %{
        total_saves: over(count(), :all),
        title: over(first_value(l.title), :newest),
        first_username: over(first_value(u.username), :oldest),
        first_saved_at: over(first_value(l.inserted_at), :oldest),
        latest_username: over(first_value(u.username), :newest),
        latest_saved_at: over(first_value(l.inserted_at), :newest)
      },
      limit: 1
    )
    |> Repo.one()
  end

  defp current_user_bookmark(_url, nil), do: nil

  defp current_user_bookmark(url, user_id) do
    Repo.get_by(Link, url: url, user_id: user_id)
  end

  defp common_tags(url) do
    from(l in Link,
      join: u in assoc(l, :user),
      where: l.url == ^url,
      where: not l.is_private and not l.is_unread,
      where: not u.is_banned,
      inner_lateral_join: t in fragment("SELECT unnest(?) AS tag", l.tags),
      on: true,
      group_by: t.tag,
      having: count() > 1,
      order_by: [desc: count(), asc: t.tag],
      select: %{tag: t.tag, count: count()}
    )
    |> Repo.all()
  end

  defp domain_saves(url) do
    case URI.parse(url).host do
      nil ->
        0

      host ->
        # Queries the JSONB `metadata` column directly — coupled to the shape
        # written by `Link.changeset/2` (see `Link.extract_metadata/1`).
        from(l in Link,
          join: u in assoc(l, :user),
          where: fragment("?->>'host'", l.metadata) == ^host,
          where: not l.is_private and not l.is_unread,
          where: not u.is_banned
        )
        |> Repo.aggregate(:count)
    end
  end

  defp compute_granularity(earliest) do
    hours = DateTime.diff(DateTime.utc_now(), earliest, :hour)

    cond do
      hours > 180 * 24 -> :month
      hours > 14 * 24 -> :week
      hours > 24 -> :day
      true -> :hour
    end
  end

  defp activity_buckets(url, granularity) do
    buckets =
      from(l in Link,
        join: u in assoc(l, :user),
        where: l.url == ^url,
        where: not l.is_private and not l.is_unread,
        where: not u.is_banned,
        group_by: selected_as(:period),
        order_by: selected_as(:period),
        select: %{
          period:
            type(
              fragment(
                "(date_trunc(?, ?) AT TIME ZONE 'UTC')",
                ^to_string(granularity),
                l.inserted_at
              ),
              :utc_datetime
            )
            |> selected_as(:period),
          count: count()
        }
      )
      |> Repo.all()

    case buckets do
      [] ->
        []

      _ ->
        counts = Map.new(buckets, fn %{period: period, count: count} -> {period, count} end)

        start_period = hd(buckets).period
        now = DateTime.truncate(DateTime.utc_now(), :second)

        all_periods(start_period, now, granularity)
        |> Enum.map(fn period ->
          %{period: period, count: Map.get(counts, period, 0)}
        end)
    end
  end

  defp all_periods(start_dt, end_dt, :hour) do
    Stream.iterate(start_dt, &DateTime.add(&1, 1, :hour))
    |> Enum.take_while(&(DateTime.compare(&1, end_dt) != :gt))
  end

  defp all_periods(start_dt, end_dt, :day) do
    Stream.iterate(start_dt, &DateTime.add(&1, 1, :day))
    |> Enum.take_while(&(DateTime.compare(&1, end_dt) != :gt))
  end

  defp all_periods(start_dt, end_dt, :week) do
    Stream.iterate(start_dt, &DateTime.add(&1, 7, :day))
    |> Enum.take_while(&(DateTime.compare(&1, end_dt) != :gt))
  end

  defp all_periods(start_dt, end_dt, :month) do
    Stream.iterate(start_dt, fn dt ->
      dt
      |> DateTime.to_date()
      |> Date.add(32)
      |> Date.beginning_of_month()
      |> DateTime.new!(Time.new!(0, 0, 0), "Etc/UTC")
    end)
    |> Enum.take_while(&(DateTime.compare(&1, end_dt) != :gt))
  end
end
