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

  embed_templates "../templates/link/*"

  attr :link, Linkhut.Links.Link, required: true
  attr :scope, Utils.Scope, required: true

  def link_tags(assigns) do
    ~H"""
    <div class="tags">
      <h5 class="label"><%= gettext("Tags:") %></h5>
      <ul class="tags" data-label={gettext("tags")}>
        <.link_tag :for={tag <- @link.tags} path={html_path(@scope, tag: tag)} tag={tag} />
      </ul>
    </div>
    """
  end

  attr :tag, :string, required: true
  attr :path, :string, required: true
  attr :rest, :global

  def link_tag(assigns) do
    ~H"""
    <li><a href={@path} {@rest}><%= @tag %></a></li>
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
end
