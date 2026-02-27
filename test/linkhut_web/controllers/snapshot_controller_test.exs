defmodule LinkhutWeb.SnapshotControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Archiving

  setup {LinkhutWeb.ConnCase, :register_and_log_in_paying_user}

  defp create_link_and_snapshot(%{user: user}) do
    link = insert(:link, user_id: user.id)

    archive =
      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :complete
      )

    data_dir = Linkhut.Config.archiving(:data_dir)
    file_path = Path.join(data_dir, "test_file")
    storage_key = "local:" <> file_path

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        type: "singlefile",
        state: :complete,
        storage_key: storage_key,
        file_size_bytes: 1024,
        processing_time_ms: 500,
        response_code: 200,
        archive_id: archive.id,
        archive_metadata: %{
          content_type: "text/html",
          tool_name: "SingleFile",
          crawler_version: "2.0.75"
        }
      })

    # Create the backing file
    File.mkdir_p!(data_dir)
    File.write!(file_path, "<html>archived content</html>")

    on_exit(fn -> File.rm_rf(data_dir) end)

    %{link: link, snapshot: snapshot, archive: archive}
  end

  describe "GET /archive/:link_id (show - default tab)" do
    setup :create_link_and_snapshot

    test "redirects to first available type", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/type/singlefile"
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/999999")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end

    test "redirects to user page when no archives exist yet", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      conn = get(conn, ~p"/_/archive/#{link.id}")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "being prepared"
    end

    test "redirects to all when archives exist but no complete snapshots", %{
      conn: conn,
      user: user
    } do
      link = insert(:link, user_id: user.id)

      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :processing
      )

      conn = get(conn, ~p"/_/archive/#{link.id}")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
    end
  end

  describe "GET /archive/:link_id/type/:type (show - specific tab)" do
    setup :create_link_and_snapshot

    test "renders snapshot viewer for specific type", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile")
      assert html_response(conn, 200) =~ "snapshot"
    end

    test "redirects to first available type for unknown type", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/nonexistent")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/type/singlefile"
    end
  end

  describe "GET /snapshot/:token/serve (serve)" do
    setup :create_link_and_snapshot

    test "serves archive file with valid token", %{conn: conn, snapshot: snapshot} do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/#{token}/serve")

      assert response(conn, 200) =~ "archived content"
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]
    end

    test "sets restrictive CSP header without script-src when serve_host not configured", %{
      conn: conn,
      snapshot: snapshot
    } do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/#{token}/serve")

      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'none'"
      # Without serve_host, scripts are blocked to prevent XSS on the app domain
      refute csp =~ "script-src"
      assert csp =~ "style-src 'unsafe-inline'"
    end

    test "returns 403 for invalid token", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/invalid-token/serve")

      assert json_response(conn, 403)["error"] =~ "Invalid"
    end
  end

  describe "GET /archive/:link_id/type/:type/full (full)" do
    setup :create_link_and_snapshot

    test "redirects to serve URL with fresh token", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile/full")
      location = redirected_to(conn)
      assert location =~ "/_/snapshot/"
      assert location =~ "/serve"
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/999999/type/singlefile/full")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end

    test "redirects when type has no complete snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, link_id: link.id, user_id: user.id, url: link.url)

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          archive_id: archive.id
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile/full")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "GET /archive/:link_id/type/:type/download (download)" do
    setup :create_link_and_snapshot

    test "sends file as download", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile/download")
      assert response(conn, 200) =~ "archived content"
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "snapshot-"
      assert disposition =~ ".html"
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/999999/type/singlefile/download")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end

    test "redirects when type has no complete snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, link_id: link.id, user_id: user.id, url: link.url)

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          archive_id: archive.id
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile/download")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "GET /archive/:link_id/all (index)" do
    setup :create_link_and_snapshot

    test "lists archives grouped for a link", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "archive-group"
    end

    test "shows failed archive with error message", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :failed,
        error: "HEAD preflight: connection refused"
      )

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "HEAD preflight: connection refused"
      assert body =~ "Failed"
    end

    test "redirects when only pending_deletion archives exist", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :pending_deletion
      )

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "being prepared"
    end

    test "shows processing state for processing archive with pending snapshots", %{
      conn: conn,
      user: user
    } do
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :processing
        )

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          archive_id: archive.id
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "Processing"
    end

    test "shows queued state for pending archive", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :pending
      )

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "Queued"
    end

    test "hides re-crawl button when archive is processing", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :processing
        )

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          archive_id: archive.id
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      refute body =~ "Re-crawl"
    end

    test "hides re-crawl button when archive is pending", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      insert(:archive,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :pending
      )

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      refute body =~ "Re-crawl"
    end

    test "shows re-crawl button when no archive is processing", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "Re-crawl"
    end

    test "redirects to user page when no archives exist yet", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "being prepared"
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/999999/all")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "POST /archive/:link_id/recrawl" do
    setup :create_link_and_snapshot

    test "schedules recrawl and redirects", %{conn: conn, link: link} do
      conn = post(conn, ~p"/_/archive/#{link.id}/recrawl")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Re-crawl scheduled"
    end

    test "redirects when link not found", %{conn: conn, user: user} do
      conn = post(conn, ~p"/_/archive/999999/recrawl")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "invalid link_id" do
    test "show redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/abc")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end

    test "show redirects for trailing-text link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/123abc")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end

    test "index redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/abc/all")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end

    test "full redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/abc/type/singlefile/full")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end

    test "download redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/abc/type/singlefile/download")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end

    test "recrawl redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = post(conn, ~p"/_/archive/abc/recrawl")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end
  end

  describe "authentication" do
    test "archive show requires authentication", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/archive/1")

      assert redirected_to(conn) =~ "login"
    end

    test "archive index requires authentication", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/archive/1/all")

      assert redirected_to(conn) =~ "login"
    end

    test "archive show redirects when archiving not available for user", %{conn: conn} do
      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user(:active_free)

      conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> get(~p"/_/archive/1")

      assert redirected_to(conn) == ~p"/~#{free_user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Archiving is not available"
    end
  end
end
