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
