defmodule LinkhutWeb.SnapshotHTML do
  use LinkhutWeb, :html

  alias Linkhut.Archiving

  import LinkhutWeb.NavigationComponents, only: [nav_link: 1]

  embed_templates "snapshot_html/*"

  # --- Function components ---

  attr :tabs, :list, required: true, doc: "list of crawler type strings"
  attr :link_id, :integer, required: true
  attr :request_path, :string, required: true

  def snapshot_tabs(assigns) do
    ~H"""
    <div class="navigation">
      <h2 class="navigation-header">Archive</h2>
      <ul class="navigation-tabs">
        <.nav_link
          :for={type <- @tabs}
          request_path={@request_path}
          to={~p"/_/archive/#{@link_id}/type/#{type}"}
          name={crawler_display_name(type)}
        />
        <.nav_link
          request_path={@request_path}
          to={~p"/_/archive/#{@link_id}/all"}
          name="All snapshots"
        />
      </ul>
    </div>
    <hr />
    """
  end

  attr :link, :map, required: true
  attr :snapshot, :map, required: true

  def toolbar(assigns) do
    ~H"""
    <div class="snapshot-toolbar">
      <dl class="snapshot-link">
        <dt>Title</dt>
        <dd><a rel="nofollow" href={@link.url}>{@link.title}</a></dd>
        <dt>URL</dt>
        <dd><a rel="nofollow" href={@link.url}>{@link.url}</a></dd>
      </dl>
      <div class="snapshot-nav">
        <a href={~p"/_/archive/#{@link.id}/type/#{@snapshot.type}/full"}>full page</a>
        <a href={~p"/_/archive/#{@link.id}/type/#{@snapshot.type}/download"}>download</a>
      </div>
    </div>
    """
  end

  attr :snapshot, :map, required: true
  attr :link, :map, required: true

  def details(assigns) do
    archive = assigns.snapshot.archive
    archive_steps = if archive, do: archive.steps, else: []

    assigns =
      assign(assigns, :timeline, Archiving.merge_timeline(archive_steps, [assigns.snapshot]))

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
            <td>{format_datetime(@snapshot.inserted_at)}</td>
          </tr>
          <tr>
            <th>Type</th>
            <td>{crawler_label(@snapshot)}</td>
          </tr>
          <tr :if={tool_label(@snapshot)}>
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
          <tr>
            <th>Size</th>
            <td>{format_file_size(@snapshot.file_size_bytes)}</td>
          </tr>
          <tr>
            <th>State</th>
            <td><span class={"state #{state_class(@snapshot.state)}"}>{state_label(@snapshot.state)}</span></td>
          </tr>
          <tr :if={@snapshot.retry_count && @snapshot.retry_count > 0}>
            <th>Retries</th>
            <td>{@snapshot.retry_count}</td>
          </tr>
          <tr :if={@snapshot.failed_at}>
            <th>Failed at</th>
            <td>{format_datetime(@snapshot.failed_at)}</td>
          </tr>
        </tbody>
      </table>
      <h4 :if={@timeline != []} class="step-timeline-header">Timeline</h4>
      <.step_timeline :if={@timeline != []} steps={@timeline} />
    </details>
    """
  end

  # --- Archive-centric components ---

  attr :archive, :map, required: true
  attr :link, :map, required: true

  def archive_group(assigns) do
    assigns =
      assigns
      |> assign(:max_retry_count, max_retry_count(assigns.archive.snapshots))
      |> assign(
        :timeline,
        Archiving.merge_timeline(assigns.archive.steps, assigns.archive.snapshots)
      )

    ~H"""
    <div class={"archive-group #{archive_state_class(@archive.state)}"}>
      <div class="archive-header">
        <span class="archive-time" title={format_relative_datetime(@archive.inserted_at)}>
          {format_datetime(@archive.inserted_at)}
        </span>
        <div class="archive-header-right">
          <span :if={@archive.total_size_bytes > 0} class="archive-size">
            {format_file_size(@archive.total_size_bytes)}
          </span>
          <span :if={@archive.state == :failed && @max_retry_count > 0} class="archive-retries">
            {ngettext("1 retry", "%{count} retries", @max_retry_count)}
          </span>
          <span class={"state #{archive_state_class(@archive.state)}"}>{archive_state_label(@archive.state)}</span>
        </div>
      </div>
      <div :if={@archive.error} class="archive-error">{@archive.error}</div>
      <details class="archive-details" open={@archive.state in [:failed, :processing, :pending]}>
        <summary>Details</summary>
        <.step_timeline :if={@timeline != []} steps={@timeline} />
      </details>
      <table :if={@archive.snapshots != []} class="snapshot-table">
        <thead>
          <tr>
            <th>Captured</th>
            <th>Type</th>
            <th>Tool</th>
            <th>Response</th>
            <th>Processing time</th>
            <th>Size</th>
            <th>State</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody :for={snapshot <- @archive.snapshots}>
          <tr class={state_class(snapshot.state)}>
            <td data-label="Captured" title={format_relative_datetime(snapshot.inserted_at)}>
              {format_datetime(snapshot.inserted_at)}
            </td>
            <td data-label="Type">{crawler_label(snapshot)}</td>
            <td data-label="Tool">{tool_label(snapshot)}</td>
            <td data-label="Response">{format_response_code(snapshot.response_code)}</td>
            <td data-label="Processing time">{format_processing_time(snapshot.processing_time_ms)}</td>
            <td data-label="Size">{format_file_size(snapshot.file_size_bytes)}</td>
            <td data-label="State">
              <span class={"state #{state_class(snapshot.state)}"}>{state_label(snapshot.state)}</span>
            </td>
            <td data-label="Actions">
              <a :if={snapshot.state == :complete} href={~p"/_/archive/#{@link.id}/type/#{snapshot.type}"}>view</a>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :steps, :list, required: true

  def step_timeline(assigns) do
    ~H"""
    <ol class="step-timeline">
      <li :for={step <- @steps} class={"step-timeline-item #{step_class(step)}"}>
        <time :if={step["at"]} class="step-time">{format_step_time(step["at"])}</time>
        <span :if={step["prefix"]} class="step-prefix">{step["prefix"]}</span>
        <span class="step-name">{step_display_name(step)}</span>
        <span :if={step["detail"]} class="step-detail">{LinkhutWeb.Archiving.StepDescriptions.render(step["detail"])}</span>
      </li>
    </ol>
    """
  end

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

  # --- Helper functions ---

  @doc """
  Formats a file size in bytes to a human-readable format.
  """
  defdelegate format_file_size(bytes), to: Linkhut.Formatting, as: :format_bytes

  @doc """
  Formats a datetime for display in the snapshot metadata.
  """
  def format_datetime(%DateTime{} = dt) do
    dt
    |> DateTime.to_date()
    |> Date.to_string()
  end

  def format_datetime(_), do: "Unknown"

  @doc """
  Formats processing time from milliseconds to a readable format.
  """
  def format_processing_time(nil), do: "Unknown"

  def format_processing_time(ms) when is_integer(ms) do
    cond do
      ms >= 60_000 -> "#{Float.round(ms / 60_000, 1)} min"
      ms >= 1_000 -> "#{Float.round(ms / 1_000, 1)} sec"
      true -> "#{ms} ms"
    end
  end

  @doc """
  Returns the display name for a crawler type.
  """
  def crawler_display_name("singlefile"), do: "Web page"
  def crawler_display_name("httpfetch"), do: "File"
  def crawler_display_name("wget"), do: "Wget"
  def crawler_display_name(type), do: String.capitalize(type)

  defp default_tool_name("singlefile"), do: "SingleFile"
  defp default_tool_name("httpfetch"), do: "Req"
  defp default_tool_name("wget"), do: "Wget"
  defp default_tool_name(type), do: String.capitalize(type)

  @doc """
  Formats a datetime as a relative time string (e.g. "3 days ago").
  """
  def format_relative_datetime(%DateTime{} = dt) do
    Timex.format!(dt, "{relative}", :relative)
  end

  def format_relative_datetime(_), do: "Unknown"

  @doc """
  Returns a human-readable label for an HTTP response code.
  """
  def format_response_code(nil), do: "Unknown"
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
  def state_label(:retryable), do: "Retrying"
  def state_label(:complete), do: "Complete"
  def state_label(:failed), do: "Failed"
  def state_label(:pending_deletion), do: "Pending deletion"
  def state_label(_), do: "Unknown"

  @doc """
  Returns a CSS class suffix for a snapshot state.
  """
  def state_class(:pending), do: "pending"
  def state_class(:crawling), do: "crawling"
  def state_class(:retryable), do: "retryable"
  def state_class(:complete), do: "complete"
  def state_class(:failed), do: "failed"
  def state_class(:pending_deletion), do: "pending-deletion"
  def state_class(_), do: ""

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
  def crawler_version(%{crawler_meta: %{"version" => v}}) when not is_nil(v), do: v
  def crawler_version(_), do: nil

  @doc """
  Returns the crawler type display name.
  E.g. "SingleFile" or "HTTP Fetch".
  """
  def crawler_label(snapshot) do
    crawler_display_name(snapshot_type(snapshot))
  end

  @doc """
  Extracts the tool name from a snapshot's crawler_meta.
  Returns nil if not available.
  """
  def tool_name(%{crawler_meta: %{"tool_name" => name}}) when is_binary(name), do: name
  def tool_name(_), do: nil

  @doc """
  Returns a combined tool label with name and optional version.
  E.g. "Req 0.5.8" or "SingleFile 1.2.3".
  Returns nil if tool name is not available.
  """
  def tool_label(snapshot) do
    case tool_name(snapshot) do
      nil ->
        case crawler_version(snapshot) do
          nil -> nil
          version -> "#{default_tool_name(snapshot_type(snapshot))} #{version}"
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
  Returns a human-readable label for an archive state.
  """
  def archive_state_label(:pending), do: "Queued"
  def archive_state_label(:processing), do: "Processing"
  def archive_state_label(:complete), do: "Complete"
  def archive_state_label(:failed), do: "Failed"
  def archive_state_label(:pending_deletion), do: "Pending deletion"
  def archive_state_label(_), do: "Unknown"

  @doc """
  Returns a CSS class suffix for an archive state.
  """
  def archive_state_class(:pending), do: "pending"
  def archive_state_class(:processing), do: "processing"
  def archive_state_class(:complete), do: "complete"
  def archive_state_class(:failed), do: "failed"
  def archive_state_class(:pending_deletion), do: "pending-deletion"
  def archive_state_class(_), do: ""

  @doc """
  Formats an ISO 8601 timestamp string for step timeline display.
  Returns a short time representation or the raw string on error.
  """
  def format_step_time(nil), do: ""

  def format_step_time(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> iso_string
    end
  end

  def format_step_time(_), do: ""

  @doc """
  Extracts the original URL from a snapshot's archive_metadata.
  Returns nil if not available.
  """
  def original_url(%{archive_metadata: %{"original_url" => url}}) when is_binary(url), do: url
  def original_url(_), do: nil

  @doc """
  Extracts crawl steps from a snapshot's crawl_info.
  Returns an empty list if not available.
  """
  defdelegate crawl_steps(snapshot), to: Linkhut.Archiving

  @doc """
  Returns true if any archive is still being processed (active with no complete snapshots).
  """
  def any_processing?(archives) do
    Enum.any?(archives, &(&1.state in [:pending, :processing]))
  end

  @doc """
  Returns a CSS class for a pipeline step based on its name.
  """
  def step_class(%{"step" => "failed"}), do: "step-failed"
  def step_class(%{"step" => "complete"}), do: "step-complete"
  def step_class(%{"step" => "completed"}), do: "step-complete"
  def step_class(_), do: ""

  @doc """
  Returns a human-readable display name for a pipeline step.
  """
  def step_display_name(%{"step" => step}) when is_binary(step) do
    step |> String.replace("_", " ") |> String.capitalize()
  end

  def step_display_name(_), do: "Unknown"

  @doc """
  Extracts the content type from a snapshot's archive_metadata.
  Returns nil if not available.
  """
  def content_type(%{archive_metadata: %{"content_type" => ct}}) when is_binary(ct), do: ct
  def content_type(_), do: nil

  @doc """
  Returns the maximum retry_count across a list of snapshots.
  Returns 0 for empty lists or when all counts are nil/0.
  """
  def max_retry_count([]), do: 0

  def max_retry_count(snapshots) when is_list(snapshots) do
    snapshots
    |> Enum.map(&(Map.get(&1, :retry_count) || 0))
    |> Enum.max(fn -> 0 end)
  end

  defp snapshot_type(%{type: type}), do: type
  defp snapshot_type(_), do: "unknown"
end
