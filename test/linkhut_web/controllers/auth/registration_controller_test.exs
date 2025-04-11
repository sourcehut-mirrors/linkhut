defmodule LinkhutWeb.Auth.RegistrationControllerTest do
  use LinkhutWeb.ConnCase

  import Linkhut.AccountsFixtures

  describe "GET /_/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/_/register")
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ ~p"/_/login"
      assert response =~ ~p"/_/register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> LinkhutWeb.ConnCase.log_in_user(user_fixture()) |> get(~p"/_/register")

      assert redirected_to(conn) == ~p"/_/profile"
    end
  end

  describe "POST /_/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      user_attributes = valid_user_attributes()

      conn =
        post(conn, ~p"/_/register", %{
          "user" => user_attributes
        })

      # assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ "~#{user_attributes.username}"
      assert response =~ ~p"/_/profile"
      assert response =~ ~p"/_/logout"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/_/register", %{
          "user" => %{
            "username" => "user123",
            "credential" => %{"email" => "with spaces", "password" => "short"}
          }
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "has invalid format"
      assert response =~ "should be at least 6 character(s)"
    end
  end
end
