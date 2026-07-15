defmodule LinkhutWeb.LinkComponents do
  @moduledoc """
  Provides UI components for Link pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.Controllers.Utils, only: [html_path: 2, rendered_notes: 2]
  import LinkhutWeb.Helpers, only: [in_timezone: 2, time_ago: 1]

  use PhoenixHtmlSanitizer, :basic_html

  alias LinkhutWeb.Viewer
  alias LinkhutWeb.Controllers.Utils
  alias LinkhutWeb.Router.Helpers, as: Routes
  alias Linkhut.Accounts.Preferences.UserPreference
  alias Linkhut.Search

  attr :link, Linkhut.Links.Link, required: true
  attr :context, Search.Context, required: true
  attr :scope, Utils.Scope, default: nil
  attr :viewer, Viewer, required: true
  attr :show_title, :boolean, default: true
  attr :show_notes, :boolean, default: true
  attr :show_url, :boolean, required: true
  attr :show_exact_dates, :boolean, required: true

  def bookmark_card(assigns) do
    ~H"""
    <div class={["bookmark-card", highlight_owned?(@link, @viewer, @context) && "your-bookmark"]}>
      <div class="bookmark">
        <div :if={@show_title} data-posted-on={@link.inserted_at} data-saves={@link.saves} data-relevance={@link.score} class="title">
          <h4><a rel="nofollow" class="taggedlink" href={@link.url}>{@link.title}</a></h4>
          <span :if={@link.is_private} class="no-css-label">{gettext("Private")}</span>
          <a :if={show_saves?(@link, @context)} class="savers" data-count={@link.saves} data-label={gettext("people")} href={~p"/-#{@link.url}"}></a>
        </div>
        <div :if={@show_url} class="full-url">
          <a rel="nofollow" href={@link.url}>{@link.url}</a>
        </div>
        <div :if={@show_notes} class="description">
          {sanitize(rendered_notes(@link, @viewer.user))}
        </div>
        <div class="ownership">
          <span :if={not owned?(@link, @viewer)}>
            {gettext("by")} <a href={~p"/~#{@link.user.username}"}>{@link.user.username}</a>
          </span>
          <span>
            <.bookmark_date
              datetime={@link.inserted_at}
              href={~p"/~#{@link.user.username}/-#{@link.url}"}
              exact={@show_exact_dates}
              timezone={@viewer.preferences.timezone}
            />
          </span>
          <span :if={show_saves?(@link, @context)} class="savers">
            {gettext("saved")} <a href={~p"/-#{@link.url}"}>{@link.saves}</a> {ngettext("time", "times", @link.saves)}
          </span>
        </div>
        <div class="meta">
          <.link_tags scope={@scope} link={@link} />
          <div :if={logged_in?(@viewer)} class="actions">
            <h5 class="label">{gettext("Actions:")}</h5>
            <ul class="actions">
              <%= if owned?(@link, @viewer) do %>
                <li>
                  <a href={~p"/_/edit?#{%{url: @link.url}}"}>{gettext("edit")}</a>
                </li>
                <li>
                  <a href={~p"/_/delete?#{%{url: @link.url}}"}>{gettext("delete")}</a>
                </li>
                <li :if={@link.is_unread}>
                  <.form for={%{}} action={~p"/_/edit"} method="put">
                    <input type="hidden" name="link[url]" value={@link.url} />
                    <input type="hidden" name="link[is_unread]" value="false" />
                    <button type="submit">{gettext("mark as read")}</button>
                  </.form>
                </li>
                <li :if={@viewer.can_view_archives?}>
                  <a href={~p"/_/archive/#{@link.id}"}>{gettext("archive")}</a>
                </li>
              <% else %>
                <li :if={!@link.saved_by_current_user?}>
                  <a href={~p"/_/add?#{%{url: @link.url, title: @link.title, notes: @link.notes, tags: @link.tags}}"}>{gettext("copy to mine")}</a>
                </li>
              <% end %>
            </ul>
          </div>
        </div>
      </div>
      <div :if={@link.is_private or @link.is_unread} class="icons">
        <span :if={@link.is_private} data-icon-type="private" title={gettext("private")}></span>
        <span :if={@link.is_unread} data-icon-type="unread" title={gettext("unread")}></span>
      </div>
    </div>
    <hr />
    """
  end

  defp show_saves?(link, context), do: is_nil(context.url) and link.saves > 1

  attr :title, :string, required: true
  attr :url, :string, required: true
  attr :preferences, UserPreference, default: %UserPreference{}

  def bookmark_header(assigns) do
    ~H"""
    <div class="title">
      <h3><a rel="nofollow" href={@url}>{@title}</a></h3>
    </div>
    <div :if={@preferences.show_url} class="full-url">
      <a rel="nofollow" href={@url}>{@url}</a>
    </div>
    """
  end

  defp owned?(_, %Viewer{user: nil}), do: false
  defp owned?(link, %Viewer{user: user}), do: link.user_id == user.id

  defp highlight_owned?(link, %Viewer{} = viewer, context) do
    owned?(link, viewer) and not Search.Context.own_links?(context, viewer.user)
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
