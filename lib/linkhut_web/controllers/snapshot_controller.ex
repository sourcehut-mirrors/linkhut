defmodule LinkhutWeb.SnapshotController do
  use LinkhutWeb, :controller

  alias Linkhut.{Links, Archiving}
  alias LinkhutWeb.Breadcrumb

  plug :require_archiving when action in [:show, :full, :download, :index, :recrawl]

  defp require_archiving(conn, _opts) do
    user = conn.assigns.current_user

    if Archiving.enabled_for_user?(user) do
      conn
    else
      conn
      |> put_flash(:error, "Archiving is not available")
      |> redirect(to: ~p"/~#{user.username}")
      |> halt()
    end
  end

  @doc """
  Shows the snapshot viewer page with tabs for each crawler type.
  Default tab (no type param) selects the first available type.
  """
  def show(conn, %{"link_id" => link_id, "type" => type}), do: show_snapshot(conn, link_id, type)
  def show(conn, %{"link_id" => link_id}), do: show_snapshot(conn, link_id, nil)

  defp show_snapshot(conn, link_id, type) do
    user = conn.assigns.current_user

    case parse_link_id(link_id) do
      {:ok, link_id} ->
        case Links.get_user_link(link_id, user.id) do
          {:ok, link} ->
            complete = Archiving.get_complete_snapshots_by_link(link_id)
            render_snapshot_or_redirect(conn, user, link, link_id, complete, type)

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Snapshot not found")
            |> redirect(to: ~p"/~#{user.username}")
        end

      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp render_snapshot_or_redirect(conn, user, _link, link_id, [], _type) do
    if Archiving.get_archives_by_link(link_id) == [] do
      conn
      |> put_flash(:info, "Archive is being prepared, check back soon.")
      |> redirect(to: ~p"/~#{user.username}")
    else
      redirect(conn, to: ~p"/_/archive/#{link_id}/all")
    end
  end

  defp render_snapshot_or_redirect(conn, _user, _link, link_id, complete, nil = _type) do
    grouped = Enum.group_by(complete, & &1.type)
    first_type = grouped |> Map.keys() |> Enum.sort() |> hd()
    redirect(conn, to: ~p"/_/archive/#{link_id}/type/#{first_type}")
  end

  defp render_snapshot_or_redirect(conn, user, link, link_id, complete, type) do
    grouped = Enum.group_by(complete, & &1.type)
    tabs = grouped |> Map.keys() |> Enum.sort()

    if type in tabs do
      snapshot = grouped[type] |> hd()
      token = Archiving.generate_token(snapshot.id)

      render(conn, :show, %{
        link: link,
        snapshot: snapshot,
        tabs: tabs,
        serve_url: serve_url(conn, token),
        breadcrumb: %Breadcrumb{user: user, url: link.url}
      })
    else
      redirect(conn, to: ~p"/_/archive/#{link_id}/type/#{hd(tabs)}")
    end
  end

  @doc """
  Serves the actual archive file using a token for authentication.
  Returns the HTML content directly for iframe display.
  """
  def serve(conn, %{"token" => token}) do
    with {:ok, snapshot_id} <- Archiving.verify_token(token),
         {:ok, snapshot} <- Archiving.get_complete_snapshot(snapshot_id),
         {:ok, {:file, path}} <- Archiving.Storage.resolve(snapshot.storage_key) do
      content_type = snapshot_content_type(snapshot)

      conn
      |> put_resp_header("content-type", serve_content_type_header(content_type))
      |> put_resp_header("x-frame-options", "SAMEORIGIN")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header("content-security-policy", csp_for_content_type(content_type))
      |> send_file(200, path)
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
  def full(conn, %{"link_id" => link_id, "type" => type}) do
    user = conn.assigns.current_user

    case parse_link_id(link_id) do
      {:ok, link_id} ->
        with {:ok, _link} <- Links.get_user_link(link_id, user.id),
             {:ok, snapshot} <- Archiving.get_latest_complete_snapshot(link_id, type) do
          token = Archiving.generate_token(snapshot.id)
          redirect(conn, external: serve_url(conn, token))
        else
          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Snapshot not found")
            |> redirect(to: ~p"/~#{user.username}")
        end

      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  @doc """
  Downloads the snapshot archive file.
  """
  def download(conn, %{"link_id" => link_id, "type" => type}) do
    user = conn.assigns.current_user

    case parse_link_id(link_id) do
      {:ok, link_id} ->
        with {:ok, link} <- Links.get_user_link(link_id, user.id),
             {:ok, snapshot} <- Archiving.get_latest_complete_snapshot(link_id, type),
             {:ok, {:file, path}} <- Archiving.Storage.resolve(snapshot.storage_key) do
          filename = download_filename(link.title, snapshot.inserted_at, snapshot)

          conn
          |> send_download({:file, path}, filename: filename, charset: "utf-8")
        else
          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Snapshot not found")
            |> redirect(to: ~p"/~#{user.username}")

          {:error, :invalid_storage_key} ->
            conn
            |> put_flash(:error, "Snapshot not found")
            |> redirect(to: ~p"/~#{user.username}")
        end

      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  @doc """
  Lists all archives (with nested snapshots) for a link.
  """
  def index(conn, %{"link_id" => link_id}) do
    user = conn.assigns.current_user

    case parse_link_id(link_id) do
      {:ok, link_id} ->
        render_index(conn, user, link_id)

      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp render_index(conn, user, link_id) do
    case Links.get_user_link(link_id, user.id) do
      {:ok, link} ->
        archives = Archiving.get_archives_by_link(link_id)

        if archives == [] do
          conn
          |> put_flash(:info, "Archive is being prepared, check back soon.")
          |> redirect(to: ~p"/~#{user.username}")
        else
          tabs =
            archives
            |> Enum.flat_map(& &1.snapshots)
            |> Enum.filter(&(&1.state == :complete))
            |> Enum.map(& &1.type)
            |> Enum.uniq()
            |> Enum.sort()

          conn
          |> maybe_auto_refresh(archives)
          |> render(:index, %{
            link: link,
            archives: archives,
            tabs: tabs,
            breadcrumb: %Breadcrumb{user: user, url: link.url}
          })
        end

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  @doc """
  Schedules a re-crawl for a link.
  """
  def recrawl(conn, %{"link_id" => link_id}) do
    user = conn.assigns.current_user

    case parse_link_id(link_id) do
      {:ok, link_id} ->
        case Links.get_user_link(link_id, user.id) do
          {:ok, link} ->
            Archiving.schedule_recrawl(link)

            conn
            |> put_flash(:info, "Re-crawl scheduled")
            |> redirect(to: ~p"/_/archive/#{link_id}/all")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Link not found")
            |> redirect(to: ~p"/~#{user.username}")
        end

      :error ->
        conn
        |> put_flash(:error, "Not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp parse_link_id(link_id_string) do
    case Integer.parse(link_id_string) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp maybe_auto_refresh(conn, archives) do
    if Enum.any?(archives, &(&1.state in [:pending, :processing])) do
      put_resp_header(conn, "refresh", "10")
    else
      conn
    end
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
      # Dedicated subdomain — allow inline scripts/styles for archived pages
      "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"
    else
      # Same origin — restrict scripts to prevent XSS on the app domain
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
