defmodule LinkhutWeb.SnapshotController do
  use LinkhutWeb, :controller

  alias Linkhut.{Links, Archiving}
  alias Linkhut.Archiving.{Format, LinkArchival, StorageKey}
  alias LinkhutWeb.{Breadcrumb, SnapshotTokens}

  plug :require_archives, :view when action in [:show, :full, :download, :index]
  plug :require_archives, :create when action in [:recrawl, :upload, :remove_snapshot, :delete]
  plug :load_link when action != :serve

  defp require_archives(conn, access) do
    if allowed?(conn.assigns.current_user, access) do
      conn
    else
      conn
      |> put_flash(:error, "Archiving is not available")
      |> redirect(to: ~p"/~#{conn.assigns.current_user.username}")
      |> halt()
    end
  end

  defp allowed?(user, :view), do: Archiving.can_view_archives?(user)
  defp allowed?(user, :create), do: Archiving.can_create_archives?(user)

  defp load_link(%{params: %{"link_id" => link_id}} = conn, _opts) do
    user = conn.assigns.current_user

    with {:ok, id} <- parse_link_id(link_id),
         {:ok, link} <- Links.get_user_link(id, user.id) do
      assign(conn, :link, link)
    else
      _ ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
        |> halt()
    end
  end

  @doc """
  Shows the snapshot viewer page with tabs for each format.
  Default tab (no format param) selects the first available format.
  """
  def show(conn, %{"format" => format, "source" => source}),
    do: show_snapshot(conn, format, source)

  def show(conn, %{"format" => format}), do: show_snapshot(conn, format, nil)
  def show(conn, _params), do: show_snapshot(conn, nil, nil)

  defp show_snapshot(conn, format, source) do
    %{current_user: user, link: link} = conn.assigns
    complete = Archiving.get_complete_snapshots_by_link(link.id)

    case {complete, find_snapshot(complete, format, source)} do
      {[], _} ->
        redirect(conn, to: ~p"/_/archive/#{link.id}/all")

      {_, nil} ->
        first = Enum.min_by(complete, &Format.format_sort_key(&1.format))
        redirect(conn, to: ~p"/_/archive/#{link.id}/#{first.format}/#{first.source}")

      {_, snapshot} ->
        render_snapshot(conn, user, link, snapshot, complete)
    end
  end

  defp render_snapshot(conn, user, link, snapshot, complete) do
    base = %{
      link: link,
      snapshot: snapshot,
      tabs: LinkhutWeb.SnapshotHTML.build_tabs(complete, link.id),
      breadcrumb: %Breadcrumb{user: user, url: link.url}
    }

    assigns =
      case StorageKey.parse(snapshot.storage_key) do
        {:ok, {:external, url}} ->
          Map.put(base, :external_url, url)

        _ ->
          token = SnapshotTokens.generate_token(snapshot.id)
          Map.put(base, :serve_url, serve_url(conn, token))
      end

    render(conn, :show, assigns)
  end

  defp find_snapshot(complete, format, source) do
    complete
    |> Enum.filter(&(&1.format == format))
    |> then(fn matching ->
      if source, do: Enum.find(matching, &(&1.source == source)), else: List.first(matching)
    end)
  end

  @doc """
  Serves the actual archive file using a token for authentication.
  Returns the HTML content directly for iframe display.
  """
  def serve(conn, %{"token" => token}) do
    with {:ok, snapshot_id} <- SnapshotTokens.verify_token(token),
         {:ok, snapshot} <- Archiving.get_complete_snapshot(snapshot_id),
         {:ok, instruction} <- Archiving.Storage.resolve(snapshot.storage_key) do
      case instruction do
        {:redirect, url} ->
          redirect(conn, external: url)

        {:file, path} ->
          content_type = snapshot_content_type(snapshot)

          conn
          |> put_resp_header("content-type", serve_content_type_header(content_type))
          |> put_resp_header("x-frame-options", "SAMEORIGIN")
          |> put_resp_header("x-content-type-options", "nosniff")
          |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
          |> put_resp_header("content-security-policy", csp_for_content_type(content_type))
          |> serve_file(path, snapshot.encoding)
      end
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(403)
        |> json(%{error: "Invalid or expired token"})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Snapshot not found"})

      {:error, :invalid_storage_key} ->
        conn
        |> put_status(404)
        |> json(%{error: "Snapshot not found"})
    end
  end

  @doc """
  Generates a fresh serve token and redirects to the serve URL.
  """
  def full(conn, %{"format" => format} = params) do
    %{current_user: user, link: link} = conn.assigns

    case Archiving.get_latest_complete_snapshot(link.id, format, params["source"]) do
      {:ok, snapshot} ->
        redirect_to_snapshot(conn, snapshot)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  @doc """
  Downloads the snapshot archive file.
  """
  def download(conn, %{"format" => format} = params) do
    %{current_user: user, link: link} = conn.assigns

    case Archiving.get_latest_complete_snapshot(link.id, format, params["source"]) do
      {:ok, snapshot} ->
        serve_download(conn, link, snapshot, user)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  @doc """
  Lists all archives (with nested snapshots) for a link.
  """
  def index(conn, _params) do
    %{current_user: user, link: link} = conn.assigns
    current_snapshots = Archiving.get_current_snapshots_by_link(link.id)
    complete_snapshots = Enum.filter(current_snapshots, &(&1.state == :complete))
    tabs = LinkhutWeb.SnapshotHTML.build_tabs(complete_snapshots, link.id)
    archiving? = Archiving.archiving?(link)

    conn
    |> maybe_auto_refresh(archiving?)
    |> render(:index, %{
      link: link,
      current_snapshots: current_snapshots,
      tabs: tabs,
      archiving: archiving?,
      crawlers: link |> LinkArchival.applicable_crawlers() |> Enum.map(& &1.source_type()),
      can_delete: Archiving.can_create_archives?(user),
      breadcrumb: %Breadcrumb{user: user, url: link.url}
    })
  end

  @doc """
  Schedules a re-crawl for a link.
  """
  def recrawl(conn, params) do
    link = conn.assigns.link

    {kind, message} =
      case Archiving.enqueue_recrawl(link, recrawl_opts(params)) do
        {:ok, %{conflict?: true}} -> {:info, "This link is already being archived"}
        {:ok, :nothing_to_archive} -> {:error, "No crawler can archive this link"}
        {:ok, _job} -> {:info, "Re-crawl scheduled"}
        {:error, _reason} -> {:error, "Re-crawl failed"}
      end

    conn
    |> put_flash(kind, message)
    |> redirect(to: ~p"/_/archive/#{link.id}/all")
  end

  @doc """
  Shows the snapshot deletion confirmation page.
  """
  def remove_snapshot(conn, %{"id" => id}) do
    %{current_user: user, link: link} = conn.assigns
    user_id = user.id

    with {:ok, snapshot_id} <- parse_link_id(id),
         %{user_id: ^user_id} = snapshot <- Archiving.get_snapshot_by_id(snapshot_id) do
      render(conn, :remove_snapshot, %{
        link: link,
        snapshot: snapshot,
        breadcrumb: %Breadcrumb{user: user, url: link.url}
      })
    else
      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")

      _ ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")
    end
  end

  @doc """
  Uploads a user-provided snapshot for a link.
  """
  def upload(conn, %{"upload" => %{"file" => %Plug.Upload{} = upload}}) do
    %{current_user: user, link: link} = conn.assigns

    case Archiving.upload_snapshot(link.id, user.id, upload) do
      {:ok, _snapshot} ->
        conn
        |> put_flash(:info, "Snapshot uploaded")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")

      {:error, :unsupported_format} ->
        conn
        |> put_flash(:error, "Unsupported file type.")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")

      {:error, {:file_too_large, _size, max}} ->
        conn
        |> put_flash(:error, "File too large (max #{Linkhut.Formatting.format_bytes(max)})")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Upload failed")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")
    end
  end

  def upload(conn, _params) do
    conn
    |> put_flash(:error, "No file selected")
    |> redirect(to: ~p"/_/archive/#{conn.assigns.link.id}/all")
  end

  @doc """
  Deletes a snapshot (marks it as pending_deletion).
  """
  def delete(conn, %{"id" => id, "snapshot" => %{"are_you_sure?" => "true"}}) do
    %{current_user: user, link: link} = conn.assigns

    with {:ok, snapshot_id} <- parse_link_id(id),
         {:ok, _snapshot} <- Archiving.request_snapshot_deletion(snapshot_id, user.id) do
      conn
      |> put_flash(:info, "Snapshot deleted")
      |> redirect(to: ~p"/_/archive/#{link.id}/all")
    else
      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")

      {:error, :active} ->
        conn
        |> put_flash(:error, "Cannot delete a snapshot that is still being processed")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/_/archive/#{link.id}/all")
    end
  end

  def delete(conn, %{"id" => id}) do
    conn
    |> put_flash(:error, "Please confirm you want to delete this snapshot")
    |> redirect(to: ~p"/_/archive/#{conn.assigns.link.id}/snapshot/#{id}/delete")
  end

  defp redirect_to_snapshot(conn, snapshot) do
    case Archiving.Storage.resolve(snapshot.storage_key) do
      {:ok, {:redirect, url}} ->
        redirect(conn, external: url)

      _ ->
        token = SnapshotTokens.generate_token(snapshot.id)
        redirect(conn, external: serve_url(conn, token))
    end
  end

  defp serve_download(conn, link, %{format: "reference"} = snapshot, _user) do
    conn
    |> put_flash(:info, "This snapshot is hosted externally and cannot be downloaded.")
    |> redirect(to: ~p"/_/archive/#{link.id}/#{snapshot.format}")
  end

  defp serve_download(conn, link, snapshot, user) do
    filename = download_filename(link.title, snapshot.inserted_at, snapshot)
    disposition = "attachment; filename=\"#{filename}\""

    case Archiving.Storage.resolve(snapshot.storage_key, disposition: disposition) do
      {:ok, {:file, path}} ->
        send_snapshot_download(conn, path, snapshot.encoding, filename)

      {:ok, {:redirect, url}} ->
        redirect(conn, external: url)

      {:error, _} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp recrawl_opts(%{"crawlers" => crawlers}) when is_list(crawlers) do
    configured = configured_crawler_types()
    selected = Enum.filter(crawlers, &(&1 in configured))

    if selected == [] or length(selected) == length(configured) do
      []
    else
      [only_types: selected]
    end
  end

  defp recrawl_opts(_), do: []

  defp configured_crawler_types do
    Linkhut.Config.archiving(:crawlers, [])
    |> Enum.map(& &1.source_type())
  end

  defp parse_link_id(link_id_string) do
    case Integer.parse(link_id_string) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp maybe_auto_refresh(conn, true), do: put_resp_header(conn, "refresh", "30")
  defp maybe_auto_refresh(conn, false), do: conn

  defp serve_file(conn, path, "gzip") do
    if accepts_encoding?(conn, "gzip") do
      conn
      |> put_resp_header("content-encoding", "gzip")
      |> put_resp_header("vary", "Accept-Encoding")
      |> send_file(200, path)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(406, Jason.encode!(%{error: "Snapshot requires gzip support"}))
    end
  end

  defp serve_file(conn, path, _encoding) do
    send_file(conn, 200, path)
  end

  defp accepts_encoding?(conn, encoding) do
    conn
    |> get_req_header("accept-encoding")
    |> Enum.any?(&String.contains?(&1, encoding))
  end

  defp send_snapshot_download(conn, path, "gzip", filename) do
    decompressed = path |> File.read!() |> :zlib.gunzip()

    send_download(conn, {:binary, decompressed}, filename: filename, charset: "utf-8")
  end

  defp send_snapshot_download(conn, path, _encoding, filename) do
    send_download(conn, {:file, path}, filename: filename, charset: "utf-8")
  end

  defp serve_url(conn, token) do
    host = Linkhut.Config.archiving(:serve_host, conn.host)
    url(%{conn | host: host}, ~p"/_/snapshot/#{token}/serve")
  end

  defp download_filename(title, inserted_at, snapshot) do
    timestamp = Calendar.strftime(inserted_at, "%Y%m%d-%H%M%S")
    ext = file_extension_for_snapshot(snapshot)

    slug =
      (title || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 80)

    case slug do
      "" -> "snapshot-#{timestamp}.#{ext}"
      slug -> "snapshot-#{timestamp}-#{slug}.#{ext}"
    end
  end

  defp snapshot_content_type(snapshot) do
    case snapshot.archive_metadata do
      %{"content_type" => ct} when is_binary(ct) -> ct
      _ -> "application/octet-stream"
    end
  end

  defp serve_content_type_header("text/" <> _ = ct), do: ct <> "; charset=utf-8"
  defp serve_content_type_header(ct), do: ct

  defp csp_for_content_type("text/html") do
    if Linkhut.Config.archiving(:serve_host) do
      # allow inline scripts/styles for archived pages
      "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"
    else
      # restrict scripts to prevent XSS on the app domain
      "default-src 'none'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"
    end
  end

  defp csp_for_content_type(_), do: "default-src 'none'"

  defp file_extension_for_snapshot(snapshot) do
    ct = snapshot_content_type(snapshot)

    case MIME.extensions(ct) do
      [ext | _] -> ext
      [] -> "bin"
    end
  end
end
