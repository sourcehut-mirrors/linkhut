defmodule LinkhutWeb.LinkComponents do
  @moduledoc """
  Provides UI components for Link pages.
  """
  use LinkhutWeb, :html

  import LinkhutWeb.Controllers.Utils, only: [html_path: 2]

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
  #   @show_full_dates   - when true, shows YYYY-MM-DD instead of relative time
  #   @show_title        - when false, suppresses the title row (default: true)
  #   @show_notes        - when false, suppresses the notes row (default: true)
  #
  # pagination/1 is an embedded template (pagination.html.heex) that renders
  # truncated page navigation. It expects:
  #
  #   @page  - pagination struct with :page, :num_pages, :has_prev, :has_next, etc.
  #   @scope - %Scope{} for URL generation

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
