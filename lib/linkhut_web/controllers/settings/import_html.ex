defmodule LinkhutWeb.Settings.ImportHTML do
  use LinkhutWeb, :html
  use Phoenix.Component

  defp print_overrides(overrides) do
    Enum.flat_map(overrides, fn
      {"is_private", "true"} -> ["Links will be imported as private"]
      _ -> []
    end)
  end

  def import_export(assigns) do
    ~H"""
    {LinkhutWeb.SettingsView."_menu.html"(assigns)}
    <div>
      <section class="settings">
        <h4>Import</h4>
        <p>
          Import bookmarks in the <a class="doc" href="https://en.wikipedia.org/wiki/Bookmark_(digital)#Storage">Netscape format</a>.
        </p>
        <.form :let={f} for={%{}} as={:upload} multipart action={~p"/_/import"}>
          <fieldset>
            <.input field={f[:file]} type="file" label="file" />
            <.input field={f[:is_private]} type="checkbox" label={gettext("Import all links as private")} />
          </fieldset>
          <.button type="submit">Import</.button>
        </.form>
      </section>
      <section class="settings">
        <h4>Export</h4>
        <p>
          Export your bookmarks in the <a class="doc" href="https://en.wikipedia.org/wiki/Bookmark_(digital)#Storage">Netscape format</a>.
        </p>
        <a class="button" download="bookmarks.html" href={~p"/_/download"}>Download</a>
      </section>
    </div>
    """
  end

  attr :job, Linkhut.Jobs.Import, required: true

  def import_job(assigns) do
    ~H"""
    {LinkhutWeb.SettingsView."_menu.html"(assigns)}
    <div>
      <section class="settings">
        <.summary job={@job} />
      </section>
      <.show_errors records={@job.failed_records} />
      <.show_parse_errors entries={@job.invalid_entries} />
    </div>
    """
  end

  attr :job, Linkhut.Jobs.Import, required: true

  def summary(assigns) do
    ~H"""
    <h4>Import Task Summary</h4>
    <.table
      id="test"
      rows={[
        {:state, "Status"},
        {:total, "Links in archive"},
        {:saved, "Successfully imported"},
        {:failed, "Failed to import"},
        {:invalid, "Parsing errors"},
        {:overrides, "Overrides"}
      ]}
    >
      <:col :let={{_, value}}>
        {value}
      </:col>
      <:col :let={{key, _}}>
        <%= case Map.get(@job, key) do %>
          <% value when is_atom(value) and not is_nil(value) -> %>
            {Phoenix.Naming.humanize(value)}
          <% value when is_map(value) and map_size(value) > 0 -> %>
            <%= if (overrides = print_overrides(value)) != [] do %>
              <ul>
                <li :for={override <- overrides}>{override}</li>
              </ul>
            <% else %>
              None
            <% end %>
          <% value when not is_map(value) and not is_nil(value) -> %>
            {value}
          <% _ -> %>
            N/A
        <% end %>
      </:col>
    </.table>
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
              <dt><span>{item.title}</span></dt>
              <dd>
                <div class="full-url"><span>{item.url}</span></div>
                <ul>
                  <%= for {key, [msg | _]} <- item.errors do %>
                    <li>{"#{key}: #{msg}"}</li>
                  <% end %>
                </ul>
                <ul class="actions">
                  <li>
                    <a href={~p"/_/add?#{Map.drop(Map.from_struct(item), [:id, :inserted_at, :errors])}"}>{gettext("edit and add")}</a>
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

  attr :entries, :list, required: true

  def show_parse_errors(assigns) do
    ~H"""
    <%= unless length(@entries) == 0 do %>
      <section class="settings">
        <details class="error">
          <summary>Parsing errors</summary>
          <dl>
            <%= for item <- @entries do %>
              <dd></dd>
              <dt>
                <code>{item}</code>
              </dt>
            <% end %>
          </dl>
        </details>
      </section>
    <% end %>
    """
  end
end
