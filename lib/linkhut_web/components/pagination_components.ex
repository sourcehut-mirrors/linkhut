defmodule LinkhutWeb.PaginationComponents do
  @moduledoc "Navigation components for paginated results."
  use LinkhutWeb, :html

  import LinkhutWeb.Controllers.Utils, only: [html_path: 2]

  alias Linkhut.Pagination
  alias LinkhutWeb.Controllers.Utils

  attr :page, Pagination.Page, required: true
  attr :scope, Utils.Scope, required: true

  def pagination(assigns) do
    assigns = assign(assigns, :page_numbers, page_numbers(assigns.page))

    ~H"""
    <div class="pagination">
      <.prev_button page={@page} scope={@scope} />
      <.page_number :for={number <- @page_numbers} page_number={number} current={@page.page} scope={@scope} />
      <.next_button page={@page} scope={@scope} />
    </div>
    """
  end

  attr :page, Pagination.Page, required: true
  attr :scope, Utils.Scope, required: true

  defp prev_button(assigns) do
    ~H"""
    <a :if={@page.has_prev} href={html_path(@scope, page: @page.prev_page)}>
      <span>❮</span>
      <span class="no-css-label">{gettext("Previous")}</span>
    </a>
    """
  end

  attr :page, Pagination.Page, required: true
  attr :scope, Utils.Scope, required: true

  defp next_button(assigns) do
    ~H"""
    <a :if={@page.has_next} href={html_path(@scope, page: @page.next_page)}>
      <span class="no-css-label">{gettext("Next")}</span>
      <span>❯</span>
    </a>
    """
  end

  attr :page_number, :any, required: true
  attr :current, :integer, required: true
  attr :scope, Utils.Scope, required: true

  defp page_number(%{page_number: :ellipsis} = assigns) do
    ~H"""
    <span><span>&hellip;</span></span>
    """
  end

  defp page_number(assigns) do
    ~H"""
    <a class={@page_number == @current && "active"} href={html_path(@scope, page: @page_number)}>
      <span>{@page_number}</span>
    </a>
    """
  end

  @doc false
  def page_numbers(%{num_pages: total, page: current}) do
    cond do
      total <= 1 -> []
      total <= 7 -> Enum.to_list(1..total)
      current < 3 or current > total - 2 -> [1, 2, 3, :ellipsis, total - 2, total - 1, total]
      current == 3 -> [1, 2, 3, 4, :ellipsis, total - 1, total]
      current == total - 2 -> [1, 2, :ellipsis, total - 3, total - 2, total - 1, total]
      true -> [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end
end
