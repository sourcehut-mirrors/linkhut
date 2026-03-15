defmodule LinkhutWeb.UrlController do
  @moduledoc """
  Handles the URL detail page, showing aggregate metadata and a paginated
  timeline of all public bookmarks for a given URL.
  """
  use LinkhutWeb, :controller

  alias Linkhut.Links
  alias Linkhut.Links.Url
  alias Linkhut.Pagination
  alias Linkhut.Search
  alias Linkhut.Search.Context
  alias LinkhutWeb.Breadcrumb
  alias LinkhutWeb.Controllers.Utils

  @links_per_page 20

  defmodule TimelineEntry do
    @moduledoc """
    Presentation wrapper for a bookmark in the URL detail timeline.

    Carries display hints computed per-page for deduplicating consecutive
    titles and notes. Avoids injecting ad-hoc keys into the Ecto struct.
    """
    defstruct [:link, show_title: true, show_notes: true]
  end

  # Bare /-  — just the check-URL input
  def show(conn, %{"check_url" => check_url}) when check_url != "" do
    redirect(conn, to: ~p"/-#{Url.normalize(check_url)}")
  end

  def show(conn, %{"url" => _url, "check_url" => check_url}) when check_url != "" do
    redirect(conn, to: ~p"/-#{Url.normalize(check_url)}")
  end

  def show(conn, params) do
    url = if url_param = params["url"], do: url_param |> URI.decode() |> Url.normalize()
    current_user_id = get_in(conn.assigns, [:current_user, Access.key(:id)])

    detail = url && Links.url_detail(url, current_user_id: current_user_id)
    context = if url, do: %Context{url: url, visible_as: Utils.visible_as(conn)}
    order = parse_timeline_order(params)

    {entry_groups, page} =
      if detail do
        # Only pass order and current_user_id — sort_by is always recency
        # for the timeline view and should not be overridden via query params.
        opts =
          Utils.query_opts(conn)
          |> Keyword.drop([:sort_by, :order])
          |> Keyword.put(:order, order)

        links_query = Search.search(context, "", opts)

        page =
          links_query
          |> Pagination.page(Utils.page(params), per_page: @links_per_page)

        groups =
          page.entries
          |> annotate_entries()
          |> Enum.chunk_by(fn %TimelineEntry{link: link} ->
            DateTime.to_date(link.inserted_at)
          end)

        {groups, Map.drop(page, [:entries])}
      else
        {[], nil}
      end

    conn
    |> render(:show,
      url: url,
      detail: detail,
      entry_groups: entry_groups,
      page: page,
      order: order,
      context: context,
      scope: Utils.scope(conn),
      breadcrumb: context && Breadcrumb.from_context(context),
      show_exact_dates: true,
      show_url: false
    )
  end

  defp parse_timeline_order(%{"order" => "asc"}), do: :asc
  defp parse_timeline_order(_), do: :desc

  # Marks consecutive entries with matching titles/notes so the template
  # can suppress duplicates. This operates on the current page only —
  # the first entry of each page always shows its title and notes.
  defp annotate_entries(entries) do
    {annotated, _} =
      Enum.map_reduce(entries, {nil, nil}, fn link, {prev_title, prev_notes} ->
        entry = %TimelineEntry{
          link: link,
          show_title: link.title != prev_title,
          show_notes: link.notes != prev_notes
        }

        {entry, {link.title, link.notes}}
      end)

    annotated
  end
end
