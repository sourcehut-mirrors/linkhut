defmodule LinkhutWeb.SnapshotHTML do
  use LinkhutWeb, :html

  alias Linkhut.Archiving
  alias Linkhut.Archiving.Format
  alias Linkhut.Accounts.Preferences.UserPreference

  import LinkhutWeb.NavigationComponents, only: [nav_link: 1]

  import LinkhutWeb.Helpers, only: [format_date_absolute: 2, time_ago: 1]

  import Linkhut.Formatting, only: [format_bytes: 1, format_processing_time: 1]
  import Linkhut.Archiving.Format, only: [format_display_name: 1, source_display_name: 1]

  embed_templates "snapshot_html/*"

  # --- Function components ---

  attr :tabs, :list, required: true, doc: "list of %{name: string, to: string} maps"
  attr :link_id, :integer, required: true
  attr :request_path, :string, required: true

  def snapshot_tabs(assigns) do
    ~H"""
    <div class="navigation">
      <h2 class="navigation-header">Archive</h2>
      <ul class="navigation-tabs">
        <.nav_link
          :for={tab <- @tabs}
          request_path={@request_path}
          to={tab.to}
          name={tab.name}
        />
        <.nav_link
          request_path={@request_path}
          to={~p"/_/archive/#{@link_id}/all"}
          name="All"
        />
      </ul>
    </div>
    <hr />
    """
  end

  @doc """
  Builds tab entries from a list of complete snapshots.
  Each tab links to /:format/:source for stable, source-based URLs.
  Disambiguates labels with source name when multiple snapshots share a format.
  """
  def build_tabs(snapshots, link_id) do
    format_counts = Enum.frequencies_by(snapshots, & &1.format)

    snapshots
    |> Enum.sort_by(&Format.format_sort_key(&1.format))
    |> Enum.map(fn snapshot ->
      name =
        if format_counts[snapshot.format] > 1 do
          "#{format_display_name(snapshot.format)} (#{source_display_name(snapshot.source)})"
        else
          format_display_name(snapshot.format)
        end

      %{name: name, to: ~p"/_/archive/#{link_id}/#{snapshot.format}/#{snapshot.source}"}
    end)
  end

  attr :link, :map, required: true
  attr :snapshot, :map, required: true
  attr :preferences, UserPreference, default: %UserPreference{}
  attr :external_url, :string, default: nil

  def toolbar(assigns) do
    ~H"""
    <div class="snapshot-toolbar">
      <div class="bookmark-header">
        <LinkhutWeb.LinkComponents.bookmark_header title={@link.title} url={@link.url} preferences={@preferences} />
      </div>
      <div :if={!@external_url} class="snapshot-nav">
        <a href={~p"/_/archive/#{@link.id}/#{@snapshot.format}/#{@snapshot.source}/full"}>full page</a>
        <a href={~p"/_/archive/#{@link.id}/#{@snapshot.format}/#{@snapshot.source}/download"}>download</a>
      </div>
    </div>
    """
  end

  attr :snapshot, :map, required: true
  attr :link, :map, required: true
  attr :external_url, :string, default: nil
  attr :timezone, :string, default: nil

  def details(assigns) do
    ~H"""
    <details class="snapshot-details">
      <summary>Details</summary>
      <table class="details-table">
        <tbody>
          <tr>
            <th>URL</th>
            <td><a rel="nofollow" href={@link.url}>{@link.url}</a></td>
          </tr>
          <tr :if={original_url(@snapshot) && original_url(@snapshot) != @link.url && original_url(@snapshot) != final_url(@snapshot)}>
            <th>Original URL</th>
            <td><a rel="nofollow" href={original_url(@snapshot)}>{original_url(@snapshot)}</a></td>
          </tr>
          <tr :if={final_url(@snapshot) && final_url(@snapshot) != @link.url}>
            <th>Final URL</th>
            <td><a rel="nofollow" href={final_url(@snapshot)}>{final_url(@snapshot)}</a></td>
          </tr>
          <tr>
            <th>Captured</th>
            <td>{format_date_absolute(@snapshot.inserted_at, @timezone)}</td>
          </tr>
          <tr>
            <th>Format</th>
            <td>{format_display_name(@snapshot.format)}</td>
          </tr>
          <tr>
            <th>Source</th>
            <td>{source_display_name(@snapshot.source)}</td>
          </tr>
          <tr :if={tool_name(@snapshot) || crawler_version(@snapshot)}>
            <th>Tool</th>
            <td>{tool_label(@snapshot)}</td>
          </tr>
          <tr :if={content_type(@snapshot)}>
            <th>Content type</th>
            <td>{content_type(@snapshot)}</td>
          </tr>
          <tr :if={@snapshot.response_code}>
            <th>Response</th>
            <td>{format_response_code(@snapshot.response_code)}</td>
          </tr>
          <tr :if={@snapshot.processing_time_ms}>
            <th>Processing time</th>
            <td>{format_processing_time(@snapshot.processing_time_ms)}</td>
          </tr>
          <tr :if={@snapshot.file_size_bytes}>
            <th>Size</th>
            <td>{format_bytes(@snapshot.file_size_bytes)}</td>
          </tr>
          <tr :if={@snapshot.source == "wayback"}>
            <th>Size</th>
            <td>{format_bytes(wayback_content_length(@snapshot))}</td>
          </tr>
          <tr :if={@snapshot.source == "wayback"}>
            <th>Digest</th>
            <td><code>{wayback_digest(@snapshot)}</code></td>
          </tr>
          <tr :if={@external_url}>
            <th>External URL</th>
            <td><a rel="nofollow noopener" href={@external_url} target="_blank">{@external_url}</a></td>
          </tr>
          <tr>
            <th>State</th>
            <td>
              <.state_badge state={@snapshot.state}>{state_label(@snapshot.state)}</.state_badge>
            </td>
          </tr>
          <tr :if={@snapshot.retry_count && @snapshot.retry_count > 0}>
            <th>Retries</th>
            <td>{@snapshot.retry_count}</td>
          </tr>
          <tr :if={@snapshot.failed_at}>
            <th>Failed at</th>
            <td>{format_date_absolute(@snapshot.failed_at, @timezone)}</td>
          </tr>
        </tbody>
      </table>
    </details>
    """
  end

  # --- Current snapshots component ---

  attr :snapshots, :list, required: true
  attr :link, :map, required: true
  attr :can_delete, :boolean, default: false
  attr :timezone, :string, default: nil

  def current_snapshots(assigns) do
    ~H"""
    <section class="current-snapshots">
      <p :if={@snapshots == []} class="empty-state">This link has no snapshots.</p>
      <table :if={@snapshots != []} class="snapshot-table">
        <thead>
          <tr>
            <th>Format</th>
            <th>Source</th>
            <th>Captured</th>
            <th>Tool</th>
            <th>Response</th>
            <th>Processing time</th>
            <th>Size</th>
            <th>State</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={snapshot <- @snapshots}>
            <td data-label="Format">{format_display_name(snapshot.format)}</td>
            <td data-label="Source">{source_display_name(snapshot.source)}</td>
            <td data-label="Captured" title={time_ago(snapshot.inserted_at)}>
              {format_date_absolute(snapshot.inserted_at, @timezone)}
            </td>
            <td data-label="Tool">{tool_label(snapshot)}</td>
            <td data-label="Response">{format_response_code(snapshot.response_code)}</td>
            <td data-label="Processing time">{format_processing_time(snapshot.processing_time_ms)}</td>
            <td data-label="Size">{format_bytes(snapshot.file_size_bytes)}</td>
            <td data-label="State">
              <.state_badge state={snapshot.state}>{state_label(snapshot.state)}</.state_badge>
              <span :if={snapshot.state == :failed and snapshot.archive_metadata["error_code"]} class="snapshot-error-reason">
                {error_code_label(snapshot.archive_metadata["error_code"])}
              </span>
            </td>
            <td data-label="Actions" class="snapshot-actions-cell">
              <a :if={snapshot.state == :complete} href={~p"/_/archive/#{@link.id}/#{snapshot.format}/#{snapshot.source}"}>view</a>
              <a :if={@can_delete and snapshot.state in [:complete, :not_available, :failed]} href={~p"/_/archive/#{@link.id}/snapshot/#{snapshot.id}/delete"}>delete</a>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  defp accepted_upload_types, do: Enum.join(Archiving.accepted_upload_types(), ",")

  # --- Archive-centric components ---

  attr :serve_url, :string, required: true
  attr :title, :string, default: nil

  def content_iframe(assigns) do
    ~H"""
    <div class="snapshot-content">
      <iframe
        src={@serve_url}
        sandbox="allow-scripts"
        title={"Snapshot of #{@title}"}
      >
      </iframe>
    </div>
    """
  end

  attr :external_url, :string, required: true
  attr :snapshot, :map, required: true
  attr :timezone, :string, default: nil

  def content_external(assigns) do
    ~H"""
    <div class="snapshot-content-external">
      <table class="details-table">
        <tbody>
          <tr :if={@snapshot.source == "wayback"}>
            <th>Captured</th>
            <td>{wayback_timestamp(@snapshot, @timezone)}</td>
          </tr>
          <tr>
            <th>URL</th>
            <td><a rel="nofollow noopener" href={@external_url} target="_blank">{@external_url}</a></td>
          </tr>
        </tbody>
      </table>
      <a href={@external_url} rel="nofollow noopener" target="_blank" class="button">
        View on {source_display_name(snapshot_source(@snapshot))}
      </a>
    </div>
    """
  end

  # --- Helper functions ---

  defp default_tool_name("singlefile"), do: "SingleFile"
  defp default_tool_name("httpfetch"), do: "Req"
  defp default_tool_name("wget"), do: "Wget"
  defp default_tool_name(type), do: String.capitalize(type)

  @doc """
  Returns a human-readable label for an HTTP response code.
  """
  def format_response_code(nil), do: nil
  def format_response_code(200), do: "200 OK"
  def format_response_code(301), do: "301 Moved"
  def format_response_code(302), do: "302 Found"
  def format_response_code(403), do: "403 Forbidden"
  def format_response_code(404), do: "404 Not Found"
  def format_response_code(500), do: "500 Server Error"
  def format_response_code(code) when is_integer(code), do: "#{code}"

  @doc """
  Returns a human-readable label for a snapshot state.
  """
  def state_label(:pending), do: "Pending"
  def state_label(:crawling), do: "Crawling"
  def state_label(:complete), do: "Complete"
  def state_label(:not_available), do: "Not Available"
  def state_label(:failed), do: "Failed"
  def state_label(:pending_deletion), do: "Pending deletion"
  def state_label(_), do: "Unknown"

  @doc """
  Returns a human-readable label for a snapshot error code.
  """
  def error_code_label("file_too_large"), do: gettext("file too large")
  def error_code_label("unsupported_crawler"), do: gettext("unsupported crawler")
  def error_code_label("stale"), do: gettext("timed out")
  def error_code_label("crawler_error"), do: gettext("crawler error")
  def error_code_label(_), do: gettext("unknown error")

  @doc """
  Extracts the final URL from a snapshot's archive_metadata.
  Returns nil if not available.
  """
  def final_url(%{archive_metadata: %{"final_url" => url}}) when is_binary(url), do: url
  def final_url(_), do: nil

  @doc """
  Extracts the crawler version from a snapshot's crawler_meta.
  Returns nil if not available.
  """
  def crawler_version(%{crawler_meta: %{"tool_version" => v}}) when not is_nil(v), do: v
  def crawler_version(_), do: nil

  @doc """
  Extracts the tool name from a snapshot's crawler_meta.
  Returns nil if not available.
  """
  def tool_name(%{crawler_meta: %{"tool_name" => name}}) when is_binary(name), do: name
  def tool_name(_), do: nil

  @doc """
  Returns a combined tool label with name and optional version.
  E.g. "Req 0.5.8" or "SingleFile 1.2.3".
  Returns nil if neither tool name nor version is available.
  """
  def tool_label(snapshot) do
    case tool_name(snapshot) do
      nil ->
        case crawler_version(snapshot) do
          nil -> nil
          version -> "#{default_tool_name(snapshot_source(snapshot))} #{version}"
        end

      name ->
        case crawler_version(snapshot) do
          nil -> name
          version -> "#{name} #{version}"
        end
    end
  end

  # --- Archive helpers ---

  @doc """
  Extracts the original URL from a snapshot's archive_metadata.
  Returns nil if not available.
  """
  def original_url(%{archive_metadata: %{"original_url" => url}}) when is_binary(url), do: url
  def original_url(_), do: nil

  @doc """
  Extracts the content type from a snapshot's archive_metadata.
  Returns nil if not available.
  """
  def content_type(%{archive_metadata: %{"content_type" => ct}}) when is_binary(ct), do: ct
  def content_type(_), do: nil

  @doc """
  Extracts and formats the Wayback Machine capture timestamp from archive_metadata.
  Returns nil if not available.
  """
  def wayback_timestamp(%{archive_metadata: %{"timestamp" => ts}} = _, timezone)
      when is_binary(ts) do
    case parse_wayback_timestamp(ts) do
      {:ok, dt} -> format_date_absolute(dt, timezone)
      :error -> ts
    end
  end

  @doc """
  Extracts the content length from Wayback Machine archive_metadata.
  Returns nil if not available.
  """
  def wayback_content_length(%{archive_metadata: %{"content_length" => len}})
      when is_integer(len),
      do: len

  def wayback_content_length(_), do: nil

  @doc """
  Extracts the digest from Wayback Machine archive_metadata.
  Returns nil if not available.
  """
  def wayback_digest(%{archive_metadata: %{"digest" => digest}}) when is_binary(digest),
    do: digest

  def wayback_digest(_), do: nil

  defp parse_wayback_timestamp(ts) when byte_size(ts) >= 14 do
    <<y::binary-4, m::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2, _::binary>> =
      ts

    with {year, ""} <- Integer.parse(y),
         {month, ""} <- Integer.parse(m),
         {day, ""} <- Integer.parse(d),
         {hour, ""} <- Integer.parse(h),
         {minute, ""} <- Integer.parse(mi),
         {second, ""} <- Integer.parse(s),
         {:ok, ndt} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  defp parse_wayback_timestamp(_), do: :error

  defp snapshot_source(%{source: source}), do: source
  defp snapshot_source(_), do: "unknown"
end
