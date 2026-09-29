defmodule LinkhutWeb.SnapshotControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Archiving
  alias Linkhut.Archiving.StorageKey

  setup {LinkhutWeb.ConnCase, :register_and_log_in_paying_user}

  defp dispatch_snapshot(user, link, attrs) do
    crawl_run = insert(:crawl_run, link_id: link.id)

    {:ok, snapshot} =
      create_snapshot(
        link.id,
        user.id,
        Map.merge(%{format: "webpage", source: "singlefile"}, attrs)
      )

    {crawl_run, snapshot}
  end

  defp create_link_and_snapshot(%{user: user}) do
    link = insert(:link, user_id: user.id)

    data_dir = Linkhut.Config.archiving(:data_dir)
    file_path = Path.join(data_dir, "test_file")
    storage_key = StorageKey.local(file_path)

    {crawl_run, snapshot} =
      dispatch_snapshot(user, link, %{
        state: :complete,
        storage_key: storage_key,
        file_size_bytes: 1024,
        processing_time_ms: 500,
        response_code: 200,
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

    test "redirects to first available format and source", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/webpage/singlefile"
    end

    test "redirects to the archive page when there is no complete snapshot", %{
      conn: conn,
      user: user
    } do
      link = insert(:link, user_id: user.id)

      conn = get(conn, ~p"/_/archive/#{link.id}")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
    end
  end

  describe "GET /archive/:link_id/:format/:source (show - specific tab)" do
    setup :create_link_and_snapshot

    test "renders snapshot viewer for format and source", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/webpage/singlefile")
      assert html_response(conn, 200) =~ "snapshot"
    end

    test "redirects to first available format for unknown format", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/nonexistent")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/webpage/singlefile"
    end
  end

  describe "GET /snapshot/:token/serve (serve)" do
    setup :create_link_and_snapshot

    test "serves archive file with valid token", %{conn: conn, snapshot: snapshot} do
      token = LinkhutWeb.SnapshotTokens.generate_token(snapshot.id)

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
      token = LinkhutWeb.SnapshotTokens.generate_token(snapshot.id)

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

  describe "GET /archive/:link_id/:format/full (full)" do
    setup :create_link_and_snapshot

    test "redirects to serve URL with fresh token", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/webpage/full")
      location = redirected_to(conn)
      assert location =~ "/_/snapshot/"
      assert location =~ "/serve"
    end

    test "redirects when type has no complete snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      dispatch_snapshot(user, link, %{state: :pending})

      conn = get(conn, ~p"/_/archive/#{link.id}/webpage/full")
      assert redirected_to(conn) == ~p"/~#{user.username}"
    end
  end

  describe "GET /archive/:link_id/:format/download (download)" do
    setup :create_link_and_snapshot

    test "sends file as download", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/webpage/download")
      assert response(conn, 200) =~ "archived content"
      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "snapshot-"
      assert disposition =~ ".html"
    end
  end

  describe "GET /archive/:link_id/all (index)" do
    setup :create_link_and_snapshot

    test "lists the snapshots, and doesn't refresh once archiving is done",
         %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)

      assert [_snapshots] = Floki.find(Floki.parse_document!(body), "table.snapshot-table")
      assert get_resp_header(conn, "refresh") == []
    end

    test "while a snapshot is pending or crawling, refreshes and hides the re-crawl button",
         %{conn: conn, user: user} do
      for state <- [:pending, :crawling] do
        link = insert(:link, user_id: user.id)
        dispatch_snapshot(user, link, %{state: state})

        conn = get(conn, ~p"/_/archive/#{link.id}/all")
        body = html_response(conn, 200)
        refute body =~ "Re-crawl", "for #{state}"
        assert get_resp_header(conn, "refresh") == ["30"], "for #{state}"
      end
    end

    test "while the archiver job is live, refreshes and hides the re-crawl button", %{
      conn: conn,
      user: user
    } do
      link = insert(:link, user_id: user.id)
      {:ok, _job} = Linkhut.Archiving.Workers.Archiver.enqueue(link)

      conn = get(conn, ~p"/_/archive/#{link.id}/all")
      body = html_response(conn, 200)
      refute body =~ "Re-crawl"
      assert get_resp_header(conn, "refresh") == ["30"]
    end

    test "shows a link that was never archived, with the re-crawl and upload forms",
         %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      body = conn |> get(~p"/_/archive/#{link.id}/all") |> html_response(200)

      assert body =~ "This link has no snapshots."
      assert body =~ "Re-crawl"
      assert body =~ "Upload snapshot"
    end

    test "says so when no crawler can archive the link", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id, url: "gemini://example.org/page")

      body = conn |> get(~p"/_/archive/#{link.id}/all") |> html_response(200)

      assert body =~ "No crawlers can archive this link"
      refute body =~ ~s(name="crawlers[]")
    end

    test "doesn't show crawler lines to a user who can't create archives" do
      put_override(Linkhut.Archiving, :mode, :limited)

      user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      link = insert(:link, user_id: user.id)

      body =
        build_conn()
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> get(~p"/_/archive/#{link.id}/all")
        |> html_response(200)

      refute body =~ "Re-crawl"
      refute body =~ "Upload snapshot"
    end
  end

  describe "POST /archive/:link_id/recrawl" do
    setup :create_link_and_snapshot

    test "schedules recrawl and redirects", %{conn: conn, link: link} do
      conn = post(conn, ~p"/_/archive/#{link.id}/recrawl")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Re-crawl scheduled"
    end
  end

  describe "GET /archive/:link_id/snapshot/:id/delete" do
    setup :create_link_and_snapshot

    test "renders confirmation page", %{conn: conn, link: link, snapshot: snapshot} do
      conn = get(conn, ~p"/_/archive/#{link.id}/snapshot/#{snapshot.id}/delete")
      assert html_response(conn, 200) =~ "Remove snapshot"
      assert html_response(conn, 200) =~ "Are you sure?"
    end

    test "returns not found for another user's snapshot", %{conn: conn, link: link} do
      other_user = insert(:user)
      other_link = insert(:link, user_id: other_user.id)

      {:ok, other_snapshot} =
        create_snapshot(other_link.id, other_user.id, %{
          format: "webpage",
          source: "singlefile",
          state: :complete
        })

      conn = get(conn, ~p"/_/archive/#{link.id}/snapshot/#{other_snapshot.id}/delete")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end
  end

  describe "DELETE /archive/:link_id/snapshot/:id" do
    setup :create_link_and_snapshot

    test "marks snapshot as pending_deletion when confirmed", %{
      conn: conn,
      link: link,
      snapshot: snapshot
    } do
      conn =
        delete(conn, ~p"/_/archive/#{link.id}/snapshot/#{snapshot.id}", %{
          snapshot: %{"are_you_sure?" => "true"}
        })

      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Snapshot deleted"

      updated = Archiving.get_snapshot_by_id(snapshot.id)
      assert updated.state == :pending_deletion
    end

    test "redirects to confirmation page when not confirmed", %{
      conn: conn,
      link: link,
      snapshot: snapshot
    } do
      conn = delete(conn, ~p"/_/archive/#{link.id}/snapshot/#{snapshot.id}")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/snapshot/#{snapshot.id}/delete"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "confirm"
    end

    test "rejects deletion of active snapshot", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)

      {:ok, snapshot} =
        create_snapshot(link.id, user.id, %{
          format: "webpage",
          source: "singlefile",
          state: :pending
        })

      conn =
        delete(conn, ~p"/_/archive/#{link.id}/snapshot/#{snapshot.id}", %{
          snapshot: %{"are_you_sure?" => "true"}
        })

      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "still being processed"

      unchanged = Archiving.get_snapshot_by_id(snapshot.id)
      assert unchanged.state == :pending
    end

    test "returns not found for another user's snapshot", %{conn: conn, link: link} do
      other_user = insert(:user)
      other_link = insert(:link, user_id: other_user.id)

      {:ok, other_snapshot} =
        create_snapshot(other_link.id, other_user.id, %{
          format: "webpage",
          source: "singlefile",
          state: :complete
        })

      conn =
        delete(conn, ~p"/_/archive/#{link.id}/snapshot/#{other_snapshot.id}", %{
          snapshot: %{"are_you_sure?" => "true"}
        })

      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"

      unchanged = Archiving.get_snapshot_by_id(other_snapshot.id)
      assert unchanged.state == :complete
    end
  end

  describe "POST /archive/:link_id/upload" do
    setup :create_link_and_snapshot

    defp upload_fixture(filename, content_type, content) do
      path = Path.join(System.tmp_dir!(), filename)
      File.write!(path, content)

      %Plug.Upload{
        path: path,
        filename: filename,
        content_type: content_type
      }
    end

    test "uploads HTML file and creates snapshot", %{conn: conn, link: link} do
      upload = upload_fixture("page.html", "text/html", "<html>uploaded</html>")

      conn = post(conn, ~p"/_/archive/#{link.id}/upload", %{upload: %{file: upload}})
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Snapshot uploaded"

      snapshots = Archiving.get_complete_snapshots_by_link(link.id)
      upload_snapshot = Enum.find(snapshots, &(&1.source == "upload"))
      assert upload_snapshot
      assert upload_snapshot.format == "webpage"
      assert upload_snapshot.state == :complete
    end

    test "rejects unsupported file type", %{conn: conn, link: link} do
      upload =
        upload_fixture("foo.bin", "application/octet-stream", <<0, 1, 2, 3, 0, 255, 128, 10>>)

      conn = post(conn, ~p"/_/archive/#{link.id}/upload", %{upload: %{file: upload}})
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unsupported file type"
    end

    test "rejects file exceeding max size", %{conn: conn, link: link} do
      # Create a file larger than max_file_size
      max = Linkhut.Config.archiving(:max_file_size)
      content = String.duplicate("x", max + 1)
      upload = upload_fixture("big.html", "text/html", content)

      conn = post(conn, ~p"/_/archive/#{link.id}/upload", %{upload: %{file: upload}})
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "too large"

      refute Enum.any?(
               Linkhut.Repo.all_by(Linkhut.Archiving.Snapshot, link_id: link.id),
               &(&1.source == "upload")
             )
    end

    test "redirects with error when no file selected", %{conn: conn, link: link} do
      conn = post(conn, ~p"/_/archive/#{link.id}/upload", %{})
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/all"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No file"
    end
  end

  describe "compressed snapshots" do
    setup %{user: user} do
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run, link_id: link.id)

      data_dir = Linkhut.Config.archiving(:data_dir)
      file_path = Path.join(data_dir, "test_compressed_file.gz")
      storage_key = StorageKey.local(file_path)

      original_content = "<html>compressed archived content</html>"
      compressed = :zlib.gzip(original_content)

      {:ok, snapshot} =
        create_snapshot(link.id, user.id, %{
          format: "webpage",
          source: "singlefile",
          state: :complete,
          storage_key: storage_key,
          file_size_bytes: byte_size(compressed),
          encoding: "gzip",
          original_file_size_bytes: byte_size(original_content),
          processing_time_ms: 500,
          response_code: 200,
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
      token = LinkhutWeb.SnapshotTokens.generate_token(snapshot.id)

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
      token = LinkhutWeb.SnapshotTokens.generate_token(snapshot.id)

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
      conn = get(conn, ~p"/_/archive/#{link.id}/webpage/download")
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
        insert(:crawl_run, link_id: link.id)

      {:ok, snapshot} =
        create_snapshot(link.id, user.id, %{
          format: "reference",
          source: "wayback",
          state: :complete,
          storage_key:
            StorageKey.external("https://web.archive.org/web/20250301/https://example.com"),
          file_size_bytes: nil,
          processing_time_ms: 500,
          response_code: 200,
          archive_metadata: %{
            original_url: link.url,
            final_url: link.url,
            timestamp: "20250301120000"
          }
        })

      %{link: link, snapshot: snapshot, crawl_run: crawl_run}
    end

    test "show renders external content for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/reference")
      body = html_response(conn, 200)
      assert body =~ "Wayback Machine"
      assert body =~ "snapshot-content-external"
    end

    test "full redirects externally for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/reference/full")
      assert redirected_to(conn) == "https://web.archive.org/web/20250301/https://example.com"
    end

    test "download redirects with flash for wayback snapshot", %{conn: conn, link: link} do
      conn = get(conn, ~p"/_/archive/#{link.id}/reference/download")
      assert redirected_to(conn) == ~p"/_/archive/#{link.id}/reference"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "externally"
    end

    test "serve redirects externally for external storage key", %{conn: conn, snapshot: snapshot} do
      token = LinkhutWeb.SnapshotTokens.generate_token(snapshot.id)

      conn =
        conn
        |> recycle()
        |> get(~p"/_/snapshot/#{token}/serve")

      assert redirected_to(conn) == "https://web.archive.org/web/20250301/https://example.com"
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

      data_dir = Linkhut.Config.archiving(:data_dir)
      file_path = Path.join(data_dir, "test_free_user_file")
      storage_key = StorageKey.local(file_path)

      {:ok, _snapshot} =
        create_snapshot(link.id, free_user.id, %{
          format: "webpage",
          source: "singlefile",
          state: :complete,
          storage_key: storage_key,
          file_size_bytes: 1024,
          archive_metadata: %{content_type: "text/html"}
        })

      File.mkdir_p!(data_dir)
      File.write!(file_path, "<html>content</html>")
      on_exit(fn -> File.rm_rf(data_dir) end)

      conn =
        conn
        |> recycle()
        |> LinkhutWeb.ConnCase.log_in_user(free_user)
        |> get(~p"/_/archive/#{link.id}/webpage")

      assert html_response(conn, 200) =~ "snapshot"
    end

    test "free user cannot delete snapshots or recrawl in limited mode", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :limited)

      free_user =
        Linkhut.AccountsFixtures.user_fixture()
        |> Linkhut.AccountsFixtures.activate_user()

      link = insert(:link, user_id: free_user.id)

      for {method, path} <- [
            delete: ~p"/_/archive/#{link.id}/snapshot/1",
            post: ~p"/_/archive/#{link.id}/recrawl"
          ] do
        conn =
          conn
          |> recycle()
          |> LinkhutWeb.ConnCase.log_in_user(free_user)
          |> dispatch(@endpoint, method, path)

        assert redirected_to(conn) == ~p"/~#{free_user.username}", "for #{method}"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Archiving is not available",
               "for #{method}"
      end
    end
  end
end
