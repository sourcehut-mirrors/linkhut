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
end
