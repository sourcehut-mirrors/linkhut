defmodule LinkhutWeb.LinkHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.Helpers
  import LinkhutWeb.FormHelpers
  import LinkhutWeb.Controllers.Utils

  use Phoenix.HTML
  use PhoenixHtmlSanitizer, :basic_html

  alias LinkhutWeb.Router.Helpers, as: Routes
  alias Linkhut.Search.Context
  alias LinkhutWeb.Controllers.Utils
  alias LinkhutWeb.Controllers.Utils.Tags

  embed_templates "../templates/link/*"

  attr :link, Linkhut.Links.Link, required: true
  attr :scope, Utils.Scope, required: true

  def link_tags(assigns) do
    ~H"""
    <div class="tags">
      <%= if @link.tags != [] do %>
        <h5 class="label">{gettext("Tags:")}</h5>
        <ul class="tags" data-label={gettext("tags")}>
          <.link_tag :for={tag <- @link.tags} path={html_path(@scope, tag: tag)} tag={tag} />
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

  def is_search_result?(%Plug.Conn{query_params: params} = _conn) do
    case params do
      %{"query" => query} when is_binary(query) and query != "" -> true
      _ -> false
    end
  end

  def sort_option(%Plug.Conn{query_params: params} = conn) do
    case params do
      %{"sort" => sort_option} -> sort_option
      _ -> if is_search_result?(conn), do: "relevance", else: "recency"
    end
  end

  def order_option(%Plug.Conn{query_params: params} = _conn) do
    case params do
      %{"order" => order_option} -> order_option
      _ -> "desc"
    end
  end

  attr :scope, Utils.Scope, required: true
  attr :tag_count, :integer, required: true
  attr :tag_options, :list, required: true

  def tag_show_all(assigns) do
    ~H"""
    <div id="all-tags">
      <%= if @tag_count == 400 and Keyword.get(@tag_options, :limit) do %>
        <a href={html_path(@scope, tag_opts: [limit: false])}>{gettext("Show all tags")}</a>
      <% end %>
    </div>
    """
  end

  attr :scope, Utils.Scope, required: true
  attr :tag_options, :list, required: true

  def tag_sort_options(assigns) do
    ~H"""
    <div class="sort-options">
      <div>
        {gettext("Sort by:")}
        <ul>
          <li><a href={html_path(@scope, tag_opts: [sort_by: :alpha])} class={if Keyword.get(@tag_options, :sort_by, :usage) == :alpha, do: "active"}>{gettext("label")}</a></li>
          <li><a href={html_path(@scope, tag_opts: [sort_by: :usage])} class={if Keyword.get(@tag_options, :sort_by, :usage) == :usage, do: "active"}>{gettext("usage")}</a></li>
        </ul>
      </div>
      <div>
        {gettext("Order:")}
        <ul>
          <li><a href={html_path(@scope, tag_opts: [order: :asc])} class={if Keyword.get(@tag_options, :order, if(Keyword.get(@tag_options, :sort_by, :usage) == :usage, do: :desc, else: :asc)) == :asc, do: "active"}>{gettext("ascending")}</a></li>
          <li><a href={html_path(@scope, tag_opts: [order: :desc])} class={if Keyword.get(@tag_options, :order, if(Keyword.get(@tag_options, :sort_by, :usage) == :usage, do: :desc, else: :asc)) == :desc, do: "active"}>{gettext("descending")}</a></li>
        </ul>
      </div>
    </div>
    """
  end
end
