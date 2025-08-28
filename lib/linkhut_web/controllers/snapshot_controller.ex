defmodule LinkhutWeb.SnapshotController do
  use LinkhutWeb, :controller

  alias Linkhut.{Links, Archiving}

  @doc """
  Shows the snapshot viewer page with metadata and an iframe to the content.
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    id = String.to_integer(id)

    with {:ok, snapshot} <- Archiving.get_complete_snapshot(id),
         {:ok, link} <- Links.get_user_link(snapshot.link_id, user.id) do
      token = Archiving.generate_token(snapshot.id)

      render(conn, :show, %{
        link: link,
        snapshot: snapshot,
        serve_url: serve_url(conn, token)
      })
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
  Lists all archives for a link.
  """
  def index(conn, %{"link_id" => link_id}) do
    user = conn.assigns.current_user
    link_id = String.to_integer(link_id)

    with {:ok, link} <- Links.get_user_link(link_id, user.id) do
      snapshots = Links.get_link_archive_status(link_id)
      render(conn, :index, %{
        link: link,
        snapshots: snapshots
      })
    else
      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Snapshot not found")
        |> redirect(to: ~p"/~#{user.username}")
    end
  end

  defp serve_url(conn, token) do
    host = Linkhut.Config.archiving(:serve_host, conn.host)
    url(%{conn | host: host}, ~p"/_/snapshot/serve/#{token}")
  end
end
