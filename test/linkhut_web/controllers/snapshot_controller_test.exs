defmodule LinkhutWeb.SnapshotControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Archiving

  setup {LinkhutWeb.ConnCase, :register_and_log_in_user}

  defp insert_oban_job do
    {:ok, job} =
      Linkhut.Workers.Archiver.new(%{"user_id" => 1, "link_id" => 1, "url" => "https://example.com"})
      |> Oban.insert()

    job
  end

  defp create_link_and_snapshot(%{user: user}) do
    link = insert(:link, user_id: user.id)
    job = insert_oban_job()

    data_dir = Linkhut.Config.archiving(:data_dir)
    file_path = Path.join(data_dir, "test_file")
    storage_key = "local:" <> file_path

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, job.id, %{
        type: "singlefile",
        state: :complete,
        storage_key: storage_key,
        file_size_bytes: 1024,
        processing_time_ms: 500,
        response_code: 200
      })

    # Create the backing file
    File.mkdir_p!(data_dir)
    File.write!(file_path, "<html>archived content</html>")

    on_exit(fn -> File.rm_rf(data_dir) end)

    %{link: link, snapshot: snapshot}
  end

  describe "GET /snapshot/:id (show)" do
    setup :create_link_and_snapshot

    test "renders snapshot viewer for owned link", %{conn: conn, snapshot: snapshot} do
      conn = get(conn, ~p"/_/snapshot/#{snapshot.id}")
      assert html_response(conn, 200) =~ "snapshot"
    end

    test "redirects when snapshot not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/snapshot/999999")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end

    test "redirects for incomplete snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)
      job = insert_oban_job()

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, job.id, %{
          type: "singlefile",
          state: :in_progress
        })

      conn = get(conn, ~p"/_/snapshot/#{snapshot.id}")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "GET /snapshot/serve/:token (serve)" do
    setup :create_link_and_snapshot

    test "serves archive file with valid token", %{conn: conn, snapshot: snapshot} do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/serve/#{token}")

      assert response(conn, 200) =~ "archived content"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    end

    test "sets restrictive CSP header", %{conn: conn, snapshot: snapshot} do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/serve/#{token}")

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
      assert csp =~ "script-src 'unsafe-inline'"
    end

    test "returns 403 for invalid token", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/serve/invalid-token")

      assert json_response(conn, 403)["error"] =~ "Invalid"
    end
  end

  describe "GET /snapshots/:link_id (index)" do
    setup :create_link_and_snapshot

    test "lists snapshots for a link", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/snapshots/#{link.id}")
      assert html_response(conn, 200)
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/snapshots/999999")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "authentication" do
    test "snapshot show requires authentication", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/1")

      assert redirected_to(conn) =~ "login"
    end

    test "snapshot index requires authentication", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshots/1")

      assert redirected_to(conn) =~ "login"
    end
  end
end
