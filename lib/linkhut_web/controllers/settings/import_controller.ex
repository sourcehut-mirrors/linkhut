defmodule LinkhutWeb.Settings.ImportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for importing bookmarks
  """
  plug :put_view, LinkhutWeb.SettingsView

  alias Linkhut.Dump

  def show(conn, _) do
    render(conn, "import.html")
  end

  def upload(conn, %{"upload" => %{"file" => %Plug.Upload{content_type: "text/html", path: file}}}) do
    user = conn.assigns[:current_user]
    imported = Dump.import(user, File.read!(file))

    conn
    |> render("import.html", imported: imported)
  end
end
