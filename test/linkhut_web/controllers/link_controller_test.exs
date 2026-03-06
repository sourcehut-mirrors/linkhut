defmodule LinkhutWeb.LinkControllerTest do
  use LinkhutWeb.ConnCase

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
end
