defmodule Linkhut.Web.LinkControllerTest do
  use Linkhut.Web.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200)
  end

  test "add link: succeeds", %{conn: conn} do
    user = insert(:user)
    {:ok, token, _} = encode_and_sign(user, %{}, token_type: :access)

    redirect_path =
    conn
    |> put_req_header("authorization", "bearer: " <> token)
    |> post(Routes.link_path(conn, :save), %{link: params_for(:link, tags: "test auto-generated", user_id: user.id)})
    |> redirected_to(302)

    assert redirect_path == "/~#{user.username}"
  end
end
