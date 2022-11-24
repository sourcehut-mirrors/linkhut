defmodule LinkhutWeb.SettingsView do
  use LinkhutWeb, :view

  use Phoenix.HTML

  @doc """
  Generates a bookmarklet link to add the current page to this linkhut instance
  """
  def bookmarklet(conn) do
    new_link_url = Routes.link_url(conn, :new)

    get_url_js = "encodeURIComponent(document.location)"
    get_title_js = "encodeURIComponent(document.title)"

    get_notes_js =
      "(document.querySelector('meta[name=\"description\"]')!=null?document.querySelector('meta[name=\"description\"]').content:%22%22)"

    get_tags_js =
      "(document.querySelector('meta[name=\"keywords\"]')!=null?document.querySelector('meta[name=\"keywords\"]').content:%22%22)"

    "javascript:window.location=%22#{new_link_url}?url=%22+#{get_url_js}+%22&title=%22+#{get_title_js}+%22&notes=%22+#{get_notes_js}+%22&tags=%22+#{get_tags_js}"
  end

  def nav_link(conn, text, opts) do
    active? = active_path?(conn, opts)

    class =
      if active? do
        "active"
      else
        ""
      end

    opts = Keyword.put(opts, :class, class)
    link = make_link(active?, text, opts)

    if tag = opts[:wrap_with] do
      content_tag(tag, link, class: class)
    else
      link
    end
  end

  def active_path?(conn, opts) do
    to = Keyword.get(opts, :to, "")
    starts_with_path?(conn.request_path, to)
  end

  # NOTE: root path is an exception, otherwise it would be active all the time
  defp starts_with_path?(request_path, "/") when request_path != "/", do: false

  defp starts_with_path?(request_path, to) do
    # Parse both paths to strip any query parameters
    %{path: request_path} = URI.parse(request_path)
    %{path: to_path} = URI.parse(to)

    String.starts_with?(request_path, String.trim_trailing(to_path, "/"))
  end

  defp make_link(active?, text, opts) do
    if active? do
      content_tag(:span, text, opts)
    else
      link(text, opts)
    end
  end
end
