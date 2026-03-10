defmodule LinkhutWeb.Settings.StatsController do
  @moduledoc "Controller for user statistics settings page."

  use LinkhutWeb, :controller

  def show(conn, _) do
    user = conn.assigns.current_user

    link_stats = Linkhut.Links.link_stats(user)
    tag_count = Linkhut.Tags.count_tags(user)

    archive_stats =
      if conn.assigns.can_view_archives?,
        do: Linkhut.Archiving.archive_stats_for_user(user),
        else: nil

    render(conn, :stats,
      link_stats: link_stats,
      tag_count: tag_count,
      archive_stats: archive_stats
    )
  end
end
