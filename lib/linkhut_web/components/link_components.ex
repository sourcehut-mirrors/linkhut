defmodule LinkhutWeb.LinkComponents do
  @moduledoc """
  Provides UI components for Link pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.Controllers.Utils, only: [html_path: 2]
  import LinkhutWeb.Helpers, only: [in_timezone: 2, time_ago: 1]

  use PhoenixHtmlSanitizer, :basic_html

  alias LinkhutWeb.Controllers.Utils
  alias LinkhutWeb.Router.Helpers, as: Routes

  embed_templates "link_components/*"

  # bookmark_card/1 is an embedded template (bookmark_card.html.heex) that
  # renders a single bookmark entry. It expects the full parent assigns plus:
  #
  #   @link              - %Link{} struct (required)
  #   @context           - %Context{} with current search context
  #   @scope             - %Scope{} for URL generation
  #   @logged_in?        - boolean
  #   @current_user      - current user struct (when logged in)
  #   @can_view_archives? - boolean
  #   @preferences       - %UserPreference{} (from GlobalAssigns, nil when logged out)
  #   @show_title        - when false, suppresses the title row (default: true)
  #   @show_notes        - when false, suppresses the notes row (default: true)
  #
  # pagination/1 is an embedded template (pagination.html.heex) that renders
  # truncated page navigation. It expects:
  #
  #   @page  - pagination struct with :page, :num_pages, :has_prev, :has_next, etc.
  #   @scope - %Scope{} for URL generation

  attr :title, :string, required: true
  attr :url, :string, required: true
  attr :show_url, :boolean, default: true

  def bookmark_header(assigns) do
    ~H"""
    <div class="title">
      <h3><a rel="nofollow" href={@url}>{@title}</a></h3>
    </div>
    <div :if={@show_url} class="full-url">
      <a rel="nofollow" href={@url}>{@url}</a>
    </div>
    """
  end

  defp owned?(link, assigns) do
    assigns[:logged_in?] && link.user_id == assigns[:current_user].id
  end

  defp highlight_owned?(link, assigns) do
    owned?(link, assigns) && !in_own_context?(assigns)
  end

  defp in_own_context?(assigns) do
    assigns[:logged_in?] &&
      get_in(assigns, [:context, Access.key(:from), Access.key(:id)]) ==
        assigns[:current_user].id
  end

  attr :link, Linkhut.Links.Link, required: true
  attr :scope, Utils.Scope, default: nil

  def link_tags(assigns) do
    ~H"""
    <div class="tags">
      <%= if @link.tags != [] do %>
        <h5 class="label">{gettext("Tags:")}</h5>
        <ul class="tags" data-label={gettext("tags")}>
          <.link_tag :for={tag <- @link.tags} path={tag_path(@scope, tag)} tag={tag} />
        </ul>
      <% end %>
    </div>
    """
  end

  attr :tag, :string, required: true
  attr :path, :string, required: true
  attr :rest, :global

  def link_tag(assigns) do
    ~H"""
    <li><a rel="tag" href={@path} {@rest}>{@tag}</a></li>
    """
  end

  defp tag_path(nil, tag), do: ~p"/#{tag}"
  defp tag_path(scope, tag), do: html_path(scope, tag: tag)

  attr :datetime, DateTime, required: true
  attr :href, :string, required: true
  attr :timezone, :string, default: nil
  attr :exact, :boolean, default: false

  def bookmark_date(assigns) do
    ~H"""
    <a :if={@exact} href={@href}>
      {format_exact_datetime(@datetime, @timezone)}
    </a>
    <a :if={!@exact} href={@href} title={format_tooltip_datetime(@datetime, @timezone)}>
      {format_relative_datetime(@datetime, @timezone)}
    </a>
    """
  end

  @doc """
  Returns whether to show full/exact dates.

  Checks for an explicit `:show_exact_dates` assign first (set by controllers
  that always want exact dates, e.g. the URL detail timeline), then falls
  back to the user's preference. Returns `false` when neither is set.
  """
  @spec show_exact_dates?(map()) :: boolean()
  def show_exact_dates?(assigns) do
    assigns[:show_exact_dates] || pref(assigns, :show_exact_dates) || false
  end

  @doc """
  Returns whether to show the URL below bookmark titles.

  Checks for an explicit `:show_url` assign first (set by controllers
  that need to override, e.g. the URL detail page suppresses URLs),
  then falls back to the user's preference. Returns `true` by default.
  """
  @spec show_url?(map()) :: boolean()
  def show_url?(assigns) do
    case assigns[:show_url] do
      nil -> pref(assigns, :show_url) != false
      val -> val
    end
  end

  defp format_relative_datetime(%DateTime{} = dt, timezone) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, dt)
    diff_days = div(diff_seconds, 86_400)

    cond do
      diff_days < 7 ->
        time_ago(dt)

      diff_days < 28 ->
        weeks = div(diff_days, 7)
        ngettext("1 week ago", "%{count} weeks ago", weeks, count: weeks)

      diff_days < 365 ->
        months = max(div(diff_days, 30), 1)
        ngettext("1 month ago", "%{count} months ago", months, count: months)

      true ->
        dt |> in_timezone(timezone) |> Calendar.strftime("%b %Y")
    end
  end

  defp format_exact_datetime(%DateTime{} = dt, timezone) do
    dt |> in_timezone(timezone) |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp format_tooltip_datetime(%DateTime{} = dt, timezone) do
    dt |> in_timezone(timezone) |> Calendar.strftime("%Y-%m-%d %H:%M %Z")
  end

  defp pref(assigns, key) do
    get_in(assigns, [:preferences, Access.key(key)])
  end

  @doc """
  Translates a link field error, rendering an "Edit the existing entry"
  link when the URL has already been saved.

  Falls back to `CoreComponents.translate_error/1` for all other errors.
  """
  def translate_link_error({_msg, opts} = error) do
    if opts[:constraint_name] == "links_url_user_id_index" do
      edit_path = Routes.link_path(LinkhutWeb.Endpoint, :edit, url: opts[:field_value])
      translated = Gettext.dgettext(LinkhutWeb.Gettext, "errors", elem(error, 0), opts)
      assigns = %{msg: translated, edit_path: edit_path}

      ~H"""
      {@msg} <a href={@edit_path}>{gettext("Edit the existing entry")}</a>
      """
    else
      LinkhutWeb.CoreComponents.translate_error(error)
    end
  end
end
