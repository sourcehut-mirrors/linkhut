defmodule LinkhutWeb.UrlControllerTest do
  use LinkhutWeb.ConnCase

  @test_url "https://example.com"
  @missing_url "https://nonexistent.example.com"

  describe "GET /-:url" do
    test "shows empty state when no public bookmarks exist", %{conn: conn} do
      conn = get(conn, ~p"/-#{@missing_url}")
      response = html_response(conn, 200)
      assert response =~ "No public bookmarks found for this URL."
    end

    test "renders URL detail page with public bookmarks", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example Site")

      conn = get(conn, ~p"/-#{@test_url}")
      response = html_response(conn, 200)

      assert response =~ "Example Site"
      assert response =~ "example.com"
    end

    test "shows empty state when only private bookmarks exist", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, is_private: true)

      conn = get(conn, ~p"/-#{@test_url}")
      response = html_response(conn, 200)
      assert response =~ "No public bookmarks found for this URL."
    end

    test "redirects when check_url is provided", %{conn: conn} do
      other_url = "https://other.com"
      conn = get(conn, ~p"/-#{@test_url}?check_url=#{other_url}")
      assert redirected_to(conn) =~ "other.com"
    end

    test "does not redirect when check_url is empty", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example")

      conn = get(conn, ~p"/-#{@test_url}?check_url=")
      assert html_response(conn, 200)
    end

    test "respects order=asc parameter", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example")

      conn = get(conn, ~p"/-#{@test_url}?order=asc")
      response = html_response(conn, 200)
      assert response =~ "oldest first"
    end

    test "defaults to newest first ordering", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example")

      conn = get(conn, ~p"/-#{@test_url}")
      response = html_response(conn, 200)
      assert response =~ "newest first"
    end

    test "ignores sort_by query parameter", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example")

      # sort=popularity should be ignored for the URL detail timeline
      conn = get(conn, ~p"/-#{@test_url}?sort=popularity")
      assert html_response(conn, 200)
    end

    test "shows 'Edit your bookmark' when logged-in user has saved the URL", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example")

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(user)
        |> get(~p"/-#{@test_url}")

      response = html_response(conn, 200)
      assert response =~ "Edit your bookmark"
    end

    test "normalizes mixed-case scheme and host in URL lookup", %{conn: conn} do
      user = insert(:user, type: :active)
      insert(:link, user_id: user.id, url: @test_url, title: "Example Site")

      mixed_case_url = "HTTPS://EXAMPLE.COM"
      conn = get(conn, ~p"/-#{mixed_case_url}")
      response = html_response(conn, 200)

      assert response =~ "Example Site"
    end

    test "normalizes check_url redirect", %{conn: conn} do
      mixed_case_url = "HTTP://Example.COM/path"
      conn = get(conn, ~p"/-#{@test_url}?check_url=#{mixed_case_url}")
      location = redirected_to(conn)

      assert location =~ "example.com"
      refute location =~ "Example.COM"
    end

    test "shows 'Add to your bookmarks' when logged-in user hasn't saved the URL", %{conn: conn} do
      owner = insert(:user, type: :active)
      visitor = insert(:user, type: :active)
      insert(:link, user_id: owner.id, url: @test_url, title: "Example")

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(visitor)
        |> get(~p"/-#{@test_url}")

      response = html_response(conn, 200)
      assert response =~ "Add to your bookmarks"
    end

    test "shows 'copy to mine' when logged-in user hasn't saved the URL", %{conn: conn} do
      owner = insert(:user, type: :active)
      visitor = insert(:user, type: :active)
      insert(:link, user_id: owner.id, url: @test_url, title: "Example")

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(visitor)
        |> get(~p"/-#{@test_url}")

      assert html_response(conn, 200) =~ "copy to mine"
    end

    test "hides 'copy to mine' when logged-in user has already saved the URL", %{conn: conn} do
      owner = insert(:user, type: :active)
      visitor = insert(:user, type: :active)
      insert(:link, user_id: owner.id, url: @test_url, title: "Example")
      insert(:link, user_id: visitor.id, url: @test_url, title: "My copy")

      conn =
        conn
        |> LinkhutWeb.ConnCase.log_in_user(visitor)
        |> get(~p"/-#{@test_url}")

      refute html_response(conn, 200) =~ "copy to mine"
    end
  end

  describe "GET /-" do
    test "renders the URL lookup page", %{conn: conn} do
      conn = get(conn, ~p"/-")
      response = html_response(conn, 200)
      assert response =~ "Enter a URL above to look it up."
      assert response =~ "check_url"
    end

    test "redirects when check_url is provided", %{conn: conn} do
      conn = get(conn, ~p"/-?check_url=https://example.com")
      assert redirected_to(conn) =~ "example.com"
    end
  end
end
