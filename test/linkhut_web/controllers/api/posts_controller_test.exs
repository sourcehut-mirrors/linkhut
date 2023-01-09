defmodule LinkhutWeb.Api.PostsControllerTest do
  use LinkhutWeb.ConnCase

  test "/v1/posts/update - Unauthenticated", %{conn: conn} do
    conn = get(conn, Routes.api_posts_path(conn, :update))

    assert text_response(conn, 401) == "Unauthenticated"
  end

  test "/v1/posts/update [JSON] - empty", %{conn: conn} do
    user = insert(:user)
    token = insert(:access_token, resource_owner_id: user.id, scopes: "posts:read")

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token.token}")
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> get(Routes.api_posts_path(conn, :update))

    assert json_response(conn, 200) == %{"update_time" => "1970-01-01T00:00:00Z"}
  end

  test "/v1/posts/update [JSON]", %{conn: conn} do
    user = insert(:user)
    link = insert(:link, user_id: user.id)
    token = insert(:access_token, resource_owner_id: user.id, scopes: "posts:read")

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token.token}")
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> get(Routes.api_posts_path(conn, :update))

    assert json_response(conn, 200) == %{"update_time" => DateTime.to_iso8601(link.inserted_at)}
  end

  test "/v1/posts/get [JSON]", %{conn: conn} do
    user = insert(:user)
    link = insert(:link, user_id: user.id)
    md5 = :crypto.hash(:md5, link.url) |> Base.encode16(case: :lower)
    token = insert(:access_token, resource_owner_id: user.id, scopes: "posts:read")

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token.token}")
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> get(Routes.api_posts_path(conn, :get))

    assert json_response(conn, 200) == %{
             "posts" => [
               %{
                 "description" => link.title,
                 "extended" => link.notes,
                 "hash" => md5,
                 "href" => link.url,
                 "meta" => nil,
                 "others" => 0,
                 "shared" => "yes",
                 "tags" => "test auto-generated",
                 "time" => DateTime.to_iso8601(link.inserted_at),
                 "toread" => "no"
               }
             ]
           }
  end
end
