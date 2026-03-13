defmodule LinkhutWeb.Settings.ExportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for exporting bookmarks
  """
  alias Linkhut.DataTransfer
  alias Linkhut.DataTransfer.Exporters

  @exporters %{
    "netscape" => Exporters.Netscape
  }

  def download(conn, params) do
    format = Map.get(params, "format", "netscape")

    case Map.fetch(@exporters, format) do
      {:ok, exporter} ->
        stream_export(conn, exporter)

      :error ->
        conn
        |> put_status(400)
        |> text("Unsupported export format")
    end
  end

  defp stream_export(conn, exporter) do
    user = conn.assigns[:current_user]
    filename = "bookmarks.#{exporter.file_extension()}"

    conn =
      conn
      |> put_resp_content_type(exporter.content_type())
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
      |> send_chunked(200)

    DataTransfer.export_stream(user, fn link_stream ->
      with {:ok, conn} <- chunk(conn, exporter.render_header()),
           {:ok, conn} <- stream_links(conn, exporter, link_stream),
           {:ok, conn} <- chunk(conn, exporter.render_footer()) do
        conn
      else
        {:error, :closed} -> conn
      end
    end)
  end

  defp stream_links(conn, exporter, link_stream) do
    Enum.reduce_while(link_stream, {:ok, conn}, fn link, {:ok, conn} ->
      case chunk(conn, exporter.render_link(link)) do
        {:ok, conn} -> {:cont, {:ok, conn}}
        {:error, :closed} -> {:halt, {:error, :closed}}
      end
    end)
  end
end
