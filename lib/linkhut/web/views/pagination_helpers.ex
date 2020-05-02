defmodule Linkhut.Web.PaginationHelpers do
  import Phoenix.HTML.Link
  import Phoenix.HTML.Tag

  def pagination_links(page, route) do
    children = []

    children =
      if page.has_prev,
        do: children ++ link("Previous", to: route.(p: page.prev_page), class: ""),
        else: children

    children =
      if page.has_next,
        do: children ++ link("Next", to: route.(p: page.next_page), class: ""),
        else: children

    content_tag :div, class: "navigation" do
      children
    end
  end
end
