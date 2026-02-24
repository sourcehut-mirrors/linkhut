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
    link_id = String.to_integer(link_id)

    with {:ok, link} <- Links.get_user_link(link_id, user.id) do
      complete = Archiving.get_complete_snapshots_by_link(link_id)

      if complete == [] do
        redirect(conn, to: ~p"/_/archive/#{link_id}/all")
      else
        grouped = Enum.group_by(complete, & &1.type)
        tabs = grouped |> Map.keys() |> Enum.sort()
        selected_type = if type && type in tabs, do: type, else: hd(tabs)
        snapshot = grouped[selected_type] |> hd()

        token = Archiving.generate_token(snapshot.id)

        render(conn, :show, %{
          link: link,
          snapshot: snapshot,
          tabs: tabs,
          all_count: length(complete),
          serve_url: serve_url(conn, token),
          breadcrumb: %Breadcrumb{user: user, url: link.url}
        })
      end
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
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
      conn
      |> put_resp_header("content-type", "text/html; charset=utf-8")
      |> put_resp_header("x-frame-options", "SAMEORIGIN")
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> put_resp_header(
        "content-security-policy",
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:"
      )
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
    link_id = String.to_integer(link_id)

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
  end

  @doc """
  Downloads the snapshot archive file.
  """
  def download(conn, %{"link_id" => link_id, "type" => type}) do
    user = conn.assigns.current_user
    link_id = String.to_integer(link_id)

    with {:ok, link} <- Links.get_user_link(link_id, user.id),
         {:ok, snapshot} <- Archiving.get_latest_complete_snapshot(link_id, type),
         {:ok, {:file, path}} <- Archiving.Storage.resolve(snapshot.storage_key) do
      filename = download_filename(link.title, snapshot.inserted_at)

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
  end

  @doc """
  Lists all archives (with nested snapshots) for a link.
  """
  def index(conn, %{"link_id" => link_id} = params) do
    user = conn.assigns.current_user
    link_id = String.to_integer(link_id)
    show_all = params["all"] == "true"

    with {:ok, link} <- Links.get_user_link(link_id, user.id) do
      archives = Archiving.get_archives_by_link(link_id)

      all_snapshots = Enum.flat_map(archives, & &1.snapshots)
      complete = Enum.filter(all_snapshots, &(&1.state == :complete))
      other_count = length(all_snapshots) - length(complete)
      tabs = complete |> Enum.map(& &1.type) |> Enum.uniq() |> Enum.sort()

      render(conn, :index, %{
        link: link,
        archives: archives,
        show_all: show_all,
        other_count: other_count,
        tabs: tabs,
        all_count: length(complete),
        breadcrumb: %Breadcrumb{user: user, url: link.url}
      })
    else
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
    link_id = String.to_integer(link_id)

    with {:ok, link} <- Links.get_user_link(link_id, user.id) do
      Archiving.schedule_recrawl(link)

      conn
      |> put_flash(:info, "Re-crawl scheduled")
      |> redirect(to: ~p"/_/archive/#{link_id}/all")
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Link not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp serve_url(conn, token) do
    host = Linkhut.Config.archiving(:serve_host, conn.host)
    url(%{conn | host: host}, ~p"/_/snapshot/#{token}/serve")
  end

  defp download_filename(title, inserted_at) do
    timestamp = Calendar.strftime(inserted_at, "%Y%m%d-%H%M%S")

    slug =
      (title || "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 80)

    case slug do
      "" -> "snapshot-#{timestamp}.html"
      slug -> "snapshot-#{timestamp}-#{slug}.html"
    end
  end
end
