defmodule LinkhutWeb.Settings.ImportHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  def import_page(assigns) do
    ~H"""
    <%= LinkhutWeb.SettingsView."_menu.html"(assigns) %>
    <div>
      <section class="">
        <p>
          Import bookmarks in the <a class="doc" href="https://en.wikipedia.org/wiki/Bookmark_(digital)#Storage">Netscape format</a>.
        </p>
        <.form :let={f} for={%{}} as={:upload} multipart action={~p"/_/import"}>
          <fieldset>
            <.input field={f[:file]} type="file" label="file" />
          </fieldset>
          <.button type="submit">Import</.button>
        </.form>
      </section>
    </div>
    """
  end

  attr :job, Linkhut.Jobs.Import, required: true

  def import_job(assigns) do
    ~H"""
    <%= LinkhutWeb.SettingsView."_menu.html"(assigns) %>
    <div>
      <section class="settings">
        <.summary job={@job} />
      </section>
      <.show_errors records={@job.failed_records} />
    </div>
    """
  end

  attr :job, Linkhut.Jobs.Import, required: true

  def summary(assigns) do
    ~H"""
    <h4>Import Task Summary</h4>
    <table>
      <tbody>
        <%= for {key, msg} <- [
                                {:state, "Status"},
                                {:total, "Links in archive"},
                                {:saved, "Successfully imported"},
                                {:failed, "Failed to import"},
                              ] do %>
          <tr>
            <td><%= msg %></td>
            <td>
              <%= case Map.get(@job, key) do
                value when is_atom(value) and not is_nil(value) -> Phoenix.Naming.humanize(value)
                value when not is_nil(value) -> value
                _ -> "N/A"
              end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  attr :records, :list, required: true

  def show_errors(assigns) do
    ~H"""
    <%= unless length(@records) == 0 do %>
      <section class="settings">
        <details class="error">
          <summary>Failed links</summary>
          <dl>
            <%= for item <- @records do %>
              <dt><span><%= item.title %></span></dt>
              <dd>
                <div class="full-url"><span><%= item.url %></span></div>
                <ul>
                  <%= for {key, [msg | _]} <- item.errors do %>
                    <li><%= "#{key}: #{msg}" %></li>
                  <% end %>
                </ul>
                <ul class="actions">
                  <li>
                    <a href={~p"/_/add?#{Map.drop(Map.from_struct(item), [:id, :inserted_at, :errors])}"}><%= gettext("edit and add") %></a>
                  </li>
                </ul>
              </dd>
            <% end %>
          </dl>
        </details>
      </section>
    <% end %>
    """
  end
end
