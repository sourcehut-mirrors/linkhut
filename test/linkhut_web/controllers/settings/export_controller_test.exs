defmodule LinkhutWeb.Settings.ExportControllerTest do
  use LinkhutWeb.ConnCase

  setup {LinkhutWeb.ConnCase, :register_and_log_in_user}

  describe "GET /_/download" do
    test "downloads bookmarks in Netscape format", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/download")
        |> response(200)

      assert response =~ "<!DOCTYPE NETSCAPE-Bookmark-file-1>"
    end

    test "includes bookmarks in export", %{conn: conn, user: user} do
      insert(:link, user_id: user.id, url: "https://exported.example.com", title: "Exported Link")

      response =
        conn
        |> get(~p"/_/download")
        |> response(200)

      assert response =~ "https://exported.example.com"
      assert response =~ "Exported Link"
    end

    test "returns 400 for unsupported format", %{conn: conn} do
      conn = get(conn, ~p"/_/download?format=csv")

      assert response(conn, 400) =~ "Unsupported export format"
    end

    test "redirects to login page if the user is logged out" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/download")
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end
end
