defmodule LinkhutWeb.Settings.AdminControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Accounts

  setup %{conn: conn} do
    user = Linkhut.AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.set_admin_role(user)
    conn = LinkhutWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  defp set_archiving_mode(mode) do
    config = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.put(config[:archiving], :mode, mode)
    Application.put_env(:linkhut, Linkhut, Keyword.put(config, :archiving, archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, config)
    end)
  end

  describe "GET /_/admin" do
    test "renders admin page", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/admin")
        |> html_response(200)

      assert response =~ "Operational Status"
    end

    test "renders archiving section when mode is enabled", %{conn: conn} do
      set_archiving_mode(:enabled)

      response =
        conn
        |> get(~p"/_/admin")
        |> html_response(200)

      assert response =~ "Archiving"
      assert response =~ "Recompute storage"
    end
  end

  describe "POST /_/admin/recompute_storage" do
    test "recomputes storage and redirects with flash", %{conn: conn} do
      conn = post(conn, ~p"/_/admin/recompute_storage")

      assert redirected_to(conn) == "/_/admin"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Storage recomputed"
    end

    test "updates archive total_size_bytes", %{conn: conn, user: user} do
      link = insert(:link, user_id: user.id)
      archive = insert(:archive, user_id: user.id, link_id: link.id, url: link.url)
      assert archive.total_size_bytes == 0

      insert(:snapshot,
        user_id: user.id,
        link_id: link.id,
        archive_id: archive.id,
        state: :complete,
        file_size_bytes: 5000
      )

      post(conn, ~p"/_/admin/recompute_storage")

      updated = Linkhut.Repo.get(Linkhut.Archiving.Archive, archive.id)
      assert updated.total_size_bytes == 5000
    end
  end
end
