defmodule LinkhutWeb.Settings.ExportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for exporting bookmarks
  """
  alias Linkhut.Dump
  alias LinkhutWeb.Settings.ExportHTML

  def download(conn, _) do
    user = conn.assigns[:current_user]
    links = Dump.export(user)

    bookmarks = ExportHTML.bookmarks_netscape(links: links)

    conn
    |> send_download({:binary, bookmarks}, filename: "bookmarks.html", content_type: "text/html")
  end
end
