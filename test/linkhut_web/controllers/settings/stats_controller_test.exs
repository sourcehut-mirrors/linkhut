defmodule LinkhutWeb.Settings.StatsControllerTest do
  use LinkhutWeb.ConnCase, async: true

  alias Linkhut.AccountsFixtures

  describe "GET /_/stats (all users)" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = LinkhutWeb.ConnCase.log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "renders stats page with link overview", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/stats")
        |> html_response(200)

      assert response =~ "Overview"
      assert response =~ "Total bookmarks"
      assert response =~ "Private"
      assert response =~ "Unread"
      assert response =~ "Tags"
    end

    test "hides archiving stats when archiving is disabled", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :disabled)

      response =
        conn
        |> get(~p"/_/stats")
        |> html_response(200)

      assert response =~ "Total bookmarks"
      refute response =~ "Archiving"
      refute response =~ "Total storage"
    end

    test "settings menu shows Stats tab for all users", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/misc")
        |> html_response(200)

      assert response =~ ~s(href="/_/stats")
      assert response =~ "Stats"
    end
  end

  describe "GET /_/stats (archiving-enabled user)" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture() |> AccountsFixtures.activate_user(:active_free)
      conn = LinkhutWeb.ConnCase.log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows archiving stats when archiving is enabled", %{conn: conn} do
      put_override(Linkhut.Archiving, :mode, :enabled)

      response =
        conn
        |> get(~p"/_/stats")
        |> html_response(200)

      assert response =~ "Archiving"
      assert response =~ "Archived"
      assert response =~ "In progress"
      assert response =~ "Total storage"
    end

    test "shows snapshot stats when data exists", %{conn: conn, user: user} do
      put_override(Linkhut.Archiving, :mode, :enabled)

      link = insert(:link, user_id: user.id)

      archive =
        insert(:archive, user_id: user.id, link_id: link.id, url: link.url, state: :complete)

      insert(:snapshot,
        user_id: user.id,
        link_id: link.id,
        archive_id: archive.id,
        state: :complete,
        file_size_bytes: 5000,
        type: "singlefile"
      )

      response =
        conn
        |> get(~p"/_/stats")
        |> html_response(200)

      assert response =~ "Snapshots by type"
      assert response =~ "Web page"
    end
  end
end
