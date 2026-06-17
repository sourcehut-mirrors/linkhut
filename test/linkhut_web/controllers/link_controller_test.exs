defmodule LinkhutWeb.LinkControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Oauth
  alias Linkhut.Accounts.Preferences

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200)
  end

  test "add link: succeeds", %{conn: conn} do
    user = insert(:user)

    redirect_path =
      conn
      |> LinkhutWeb.ConnCase.log_in_user(user)
      |> post(Routes.link_path(conn, :insert), %{
        link: params_for(:link, tags: "test auto-generated", user_id: user.id)
      })
      |> redirected_to(302)

    assert redirect_path == "/~#{user.username}"
  end

  test "add link: shows error and edit link when URL already exists (on submit)", %{conn: conn} do
    user = insert(:user)
    link = insert(:link, user: user)

    body =
      conn
      |> LinkhutWeb.ConnCase.log_in_user(user)
      |> post(Routes.link_path(conn, :insert), %{
        link: %{url: link.url, title: "duplicate", tags: "test"}
      })
      |> html_response(200)

    assert body =~ "This URL is already in your bookmarks."
    assert body =~ "Edit the existing entry"
    assert body =~ Routes.link_path(conn, :edit, url: link.url)
  end

  test "GET /_/add: pre-checks private checkbox when default_private is true", %{conn: conn} do
    user = insert(:user)
    Preferences.upsert(user, %{default_private: true})

    body =
      conn
      |> LinkhutWeb.ConnCase.log_in_user(user)
      |> get(~p"/_/add")
      |> html_response(200)

    assert body =~ ~s(name="link[is_private]" value="true" checked)
  end

  test "GET /_/add: private checkbox is unchecked by default", %{conn: conn} do
    user = insert(:user)

    body =
      conn
      |> LinkhutWeb.ConnCase.log_in_user(user)
      |> get(~p"/_/add")
      |> html_response(200)

    refute body =~ ~s(name="link[is_private]" value="true" checked)
  end

  describe "GET /_/feed/~:username" do
    test "renders bookmark notes as HTML content", %{conn: conn} do
      user = insert(:user)
      insert(:link, user: user, is_private: false, notes_html: "<p>expected</p>")

      body =
        conn
        |> put_req_header("accept", "application/xml")
        |> get(~p"/_/feed/~#{user.username}")
        |> response(200)

      assert body =~ ~s(type="html")
      assert body =~ ~s(expected)
    end

    test "renders the authenticated bookmark's owner notes from raw markdown", %{conn: conn} do
      user = insert(:user)

      token =
        Oauth.create_token!(user, %{
          comment: "test token",
          scopes: "posts:read posts:write tags:read tags:write"
        })

      insert(:link, user: user, is_private: true, notes: "**expected**")

      body =
        conn
        |> put_req_header("accept", "application/xml")
        |> get(~p"/_/feed/~#{user.username}?auth_token=#{token.token}")
        |> response(200)

      assert body =~ ~s(type="html")
      assert body =~ ~s(&lt;strong&gt;expected&lt;/strong&gt;)
    end
  end
end
