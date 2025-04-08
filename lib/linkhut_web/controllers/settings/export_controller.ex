defmodule LinkhutWeb.Settings.ExportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for exporting bookmarks
  """
  alias Linkhut.Dump

  def download(conn, _) do
    user = conn.assigns[:current_user]
    links = Dump.export(user)

    bookmarks = Phoenix.View.render(LinkhutWeb.SettingsView, "bookmarks.netscape", links: links)

    conn
    |> send_download({:binary, bookmarks}, filename: "bookmarks.html", content_type: "html")
  end
end
