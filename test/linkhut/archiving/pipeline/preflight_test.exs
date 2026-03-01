defmodule Linkhut.Archiving.Pipeline.PreflightTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving
  alias Linkhut.Archiving.PreflightMeta
  alias Linkhut.Archiving.Pipeline.Preflight

  describe "run/1" do
    test "extracts content type and status from response" do
      {_user, _link, archive} = create_archive()
      stub_preflight(200, "text/html; charset=utf-8")

      assert {:ok, %PreflightMeta{} = meta, updated_archive} = Preflight.run(archive)
      assert meta.content_type == "text/html"
      assert meta.status == 200
      assert meta.final_url == archive.url
      assert updated_archive.final_url == archive.url
    end

    test "includes scheme in preflight_meta" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      assert {:ok, meta, _archive} = Preflight.run(archive)
      assert meta.scheme == "https"
    end

    test "captures final URL after redirect" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        case conn.request_path do
          "/page" ->
            conn
            |> Plug.Conn.put_resp_header("location", "/final-page")
            |> Plug.Conn.send_resp(301, "")

          "/final-page" ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "text/html")
            |> Plug.Conn.send_resp(200, "")
        end
      end)

      assert {:ok, meta, updated_archive} = Preflight.run(archive)
      assert meta.final_url =~ "/final-page"
      assert updated_archive.final_url =~ "/final-page"
    end

    test "returns error for unsupported scheme" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "ftp://example.com/file.txt")

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      assert {:error, {:unsupported_scheme, "ftp"}, _archive} = Preflight.run(archive)
    end

    test "returns error with content-length exceeding max" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/pdf")
        |> Plug.Conn.put_resp_header("content-length", "100000000")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:error, {:file_too_large, 100_000_000}, _archive} = Preflight.run(archive)
    end

    test "records preflight step on success" do
      {_user, _link, archive} = create_archive()
      stub_preflight()

      {:ok, _meta, updated} = Preflight.run(archive)
      assert Enum.any?(updated.steps, fn s -> s["step"] == "preflight" end)
    end

    test "records preflight_failed step on transport error" do
      {_user, _link, archive} = create_archive()

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :preflight_failed, _archive} = Preflight.run(archive)
    end
  end

  defp create_archive do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, archive} =
      Archiving.create_archive(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, archive}
  end

  defp stub_preflight(status \\ 200, content_type \\ "text/html; charset=utf-8") do
    Req.Test.stub(Linkhut.Links.Link, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", content_type)
      |> Plug.Conn.send_resp(status, "")
    end)
  end
end
