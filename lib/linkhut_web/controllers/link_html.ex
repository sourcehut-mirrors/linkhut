defmodule LinkhutWeb.LinkHTML do
  use LinkhutWeb, :html

  import LinkhutWeb.Helpers
  import LinkhutWeb.Controllers.Utils
  import LinkhutWeb.LinkComponents

  alias LinkhutWeb.Router.Helpers, as: Routes
  alias Linkhut.Search.Context
  alias LinkhutWeb.Controllers.Utils
  alias LinkhutWeb.Controllers.Utils.Tags

  embed_templates "link_html/*"

  defp tags_value(tags) when is_list(tags), do: Enum.join(tags, " ")
  defp tags_value(value), do: value

  def search_result?(%Plug.Conn{query_params: params} = _conn) do
    case params do
      %{"query" => query} when is_binary(query) and query != "" -> true
      _ -> false
    end
  end

  def sort_option(%Plug.Conn{query_params: params} = conn) do
    case params do
      %{"sort" => sort_option} -> sort_option
      _ -> if search_result?(conn), do: "relevance", else: "recency"
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
