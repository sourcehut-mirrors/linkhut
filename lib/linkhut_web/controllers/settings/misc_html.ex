defmodule LinkhutWeb.Settings.MiscHTML do
  use LinkhutWeb, :html

  embed_templates "../templates/settings/*"

  def misc(assigns) do
    ~H"""
    <%= LinkhutWeb.SettingsView."_menu.html"(assigns) %>
    <div>
      <section class="settings">
        <h4>Bookmarklet</h4>
        <p>
          When you click on this bookmarklet, it will submit the page you're on.
          To install, drag this button to your browser's toolbar:
        </p>
        <div style="text-align: center">
          <.bookmarklet />
        </div>
      </section>
    </div>
    """
  end

  def bookmarklet(assigns) do
    ~H"""
    <a class="button" href={bookmarklet()}>post to linkhut</a>
    """
  end

  defp bookmarklet() do
    new_link_url = url(LinkhutWeb.Endpoint, ~p"/_/add")

    get_url_js = "encodeURIComponent(document.location)"
    get_title_js = "encodeURIComponent(document.title)"

    get_notes_js =
      "(document.querySelector('meta[name=\"description\"]')!=null?document.querySelector('meta[name=\"description\"]').content:%22%22)"

    get_tags_js =
      "(document.querySelector('meta[name=\"keywords\"]')!=null?document.querySelector('meta[name=\"keywords\"]').content:%22%22)"

    "javascript:window.location=%22#{new_link_url}?url=%22+#{get_url_js}+%22&title=%22+#{get_title_js}+%22&notes=%22+#{get_notes_js}+%22&tags=%22+#{get_tags_js}"
  end
end
