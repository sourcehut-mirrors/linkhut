defmodule LinkhutWeb.SnapshotControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Archiving
  alias Linkhut.Archiving.StorageKey

  setup {LinkhutWeb.ConnCase, :register_and_log_in_paying_user}

  defp create_link_and_snapshot(%{user: user}) do
    link = insert(:link, user_id: user.id)

    crawl_run =
      insert(:crawl_run,
        link_id: link.id,
        user_id: user.id,
        url: link.url,
        state: :complete
      )

    data_dir = Linkhut.Config.archiving(:data_dir)
    file_path = Path.join(data_dir, "test_file")
    storage_key = StorageKey.local(file_path)

    {:ok, snapshot} =
      Archiving.create_snapshot(link.id, user.id, %{
        type: "singlefile",
        state: :complete,
        storage_key: storage_key,
        file_size_bytes: 1024,
        processing_time_ms: 500,
        response_code: 200,
        crawl_run_id: crawl_run.id,
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

    %{link: link, snapshot: snapshot, crawl_run: crawl_run}
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

      insert(:crawl_run,
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

    test "redirects when type has no complete snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)
      crawl_run = insert(:crawl_run, link_id: link.id, user_id: user.id, url: link.url)

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          crawl_run_id: crawl_run.id
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

      insert(:crawl_run,
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

      insert(:crawl_run,
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

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :processing
        )

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          crawl_run_id: crawl_run.id
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      assert body =~ "Processing"
    end

    test "shows queued state for pending archive", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      insert(:crawl_run,
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

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :processing
        )

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :pending,
          crawl_run_id: crawl_run.id
        })

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

  describe "compressed snapshots" do
    setup %{user: user} do
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :complete
        )

      data_dir = Linkhut.Config.archiving(:data_dir)
      file_path = Path.join(data_dir, "test_compressed_file.gz")
      storage_key = StorageKey.local(file_path)

      original_content = "<html>compressed archived content</html>"
      compressed = :zlib.gzip(original_content)

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "singlefile",
          state: :complete,
          storage_key: storage_key,
          file_size_bytes: byte_size(compressed),
          encoding: "gzip",
          original_file_size_bytes: byte_size(original_content),
          processing_time_ms: 500,
          response_code: 200,
          crawl_run_id: crawl_run.id,
          archive_metadata: %{
            content_type: "text/html",
            tool_name: "SingleFile",
            crawler_version: "2.0.75"
          }
        })

      File.mkdir_p!(data_dir)
      File.write!(file_path, compressed)

      on_exit(fn -> File.rm_rf(data_dir) end)

      %{
        link: link,
        snapshot: snapshot,
        crawl_run: crawl_run,
        original_content: original_content
      }
    end

    test "serves compressed file with content-encoding header", %{
      conn: conn,
      snapshot: snapshot
    } do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> put_req_header("accept-encoding", "gzip, deflate, br")
        |> get(~p"/_/snapshot/#{token}/serve")

      assert response(conn, 200)
      assert get_resp_header(conn, "content-encoding") == ["gzip"]
      assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
    end

    test "returns 406 when client does not accept gzip", %{
      conn: conn,
      snapshot: snapshot
    } do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> put_req_header("accept-encoding", "identity")
        |> get(~p"/_/snapshot/#{token}/serve")

      assert json_response(conn, 406)["error"] =~ "gzip"
    end

    test "download returns decompressed HTML", %{
      conn: conn,
      link: link,
      original_content: original_content
    } do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/singlefile/download")
      body = response(conn, 200)
      assert body == original_content

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
    end
  end

  describe "external snapshots" do
    setup %{user: user} do
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: user.id,
          url: link.url,
          state: :complete
        )

      {:ok, snapshot} =
        Archiving.create_snapshot(link.id, user.id, %{
          type: "wayback",
          state: :complete,
          storage_key:
            StorageKey.external("https://web.archive.org/web/20250301/https://example.com"),
          file_size_bytes: nil,
          processing_time_ms: 500,
          response_code: 200,
          crawl_run_id: crawl_run.id,
          archive_metadata: %{
            original_url: link.url,
            final_url: link.url
          }
        })

      %{link: link, snapshot: snapshot, crawl_run: crawl_run}
    end

    test "show renders external content for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/wayback")
      body = html_response(conn, 200)
      assert body =~ "Wayback Machine"
      assert body =~ "snapshot-content-external"
    end

    test "full redirects externally for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/wayback/full")
      assert redirected_to(conn) == "https://web.archive.org/web/20250301/https://example.com"
    end

    test "download redirects with flash for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/type/wayback/download")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/type/wayback"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "externally"
    end

    test "serve redirects externally for external storage key", %{conn: conn, snapshot: snapshot} do
      token = Archiving.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/#{token}/serve")

      assert redirected_to(conn) == "https://web.archive.org/web/20250301/https://example.com"
    end
  end

  describe "invalid link_id" do
    test "redirects for non-numeric link_id", %{conn: conn, user: user} do
      conn = get(conn, ~p"/_/archive/abc")
      assert redirected_to(conn) == ~p"/~#{user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Not found"
    end
  end

  describe "authentication" do
    test "requires authentication", %{conn: conn} do
      conn =
        conn
        |> recycle()
        |> get(~p"/_/archive/1")

      assert redirected_to(conn) =~ "login"
    end

    test "redirects when archiving is disabled for user", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :disabled)

      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> get(~p"/_/archive/1")

      assert redirected_to(conn) == ~p"/~#{free_user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Archiving is not available"
    end
  end

  describe "view/create access split" do
    test "free user can view archives in limited mode", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :limited)

      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      link = insert(:link, user_id: free_user.id)

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: free_user.id,
          url: link.url,
          state: :complete
        )

      data_dir = Linkhut.Config.archiving(:data_dir)
      file_path = Path.join(data_dir, "test_free_user_file")
      storage_key = StorageKey.local(file_path)

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, free_user.id, %{
          type: "singlefile",
          state: :complete,
          storage_key: storage_key,
          file_size_bytes: 1024,
          crawl_run_id: crawl_run.id,
          archive_metadata: %{content_type: "text/html"}
        })

      File.mkdir_p!(data_dir)
      File.write!(file_path, "<html>content</html>")
      on_exit(fn -> File.rm_rf(data_dir) end)

      conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> get(~p"/_/archive/#{link.id}/type/singlefile")

      assert html_response(conn, 200) =~ "snapshot"
    end

    test "free user cannot recrawl in limited mode", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :limited)

      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      link = insert(:link, user_id: free_user.id)

      conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> post(~p"/_/archive/#{link.id}/recrawl")

      assert redirected_to(conn) == ~p"/~#{free_user.username}"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Archiving is not available"
    end

    test "free user can view and recrawl in enabled mode", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :enabled)

      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      link = insert(:link, user_id: free_user.id)

      crawl_run =
        insert(:crawl_run,
          link_id: link.id,
          user_id: free_user.id,
          url: link.url,
          state: :complete
        )

      data_dir = Linkhut.Config.archiving(:data_dir)
      file_path = Path.join(data_dir, "test_free_enabled_file")
      storage_key = StorageKey.local(file_path)

      {:ok, _snapshot} =
        Archiving.create_snapshot(link.id, free_user.id, %{
          type: "singlefile",
          state: :complete,
          storage_key: storage_key,
          file_size_bytes: 1024,
          crawl_run_id: crawl_run.id,
          archive_metadata: %{content_type: "text/html"}
        })

      File.mkdir_p!(data_dir)
      File.write!(file_path, "<html>content</html>")
      on_exit(fn -> File.rm_rf(data_dir) end)

      # Can view
      view_conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> get(~p"/_/archive/#{link.id}/type/singlefile")

      assert html_response(view_conn, 200) =~ "snapshot"

      # Can recrawl
      recrawl_conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> post(~p"/_/archive/#{link.id}/recrawl")

      assert redirected_to(recrawl_conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(recrawl_conn.assigns.flash, :info) == "Re-crawl scheduled"
    end
  end
end
