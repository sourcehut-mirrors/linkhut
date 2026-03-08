defmodule LinkhutWeb.Settings.AdminControllerTest do
  use LinkhutWeb.ConnCase, async: true

  alias Linkhut.Accounts

  setup %{conn: conn} do
    user = Linkhut.AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.set_admin_role(user)
    conn = LinkhutWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn, user: user}
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
      put_override(Linkhut.Archiving, :mode, :enabled)

      response =
        conn
        |> get(~p"/_/admin")
        |> html_response(200)

      assert response =~ "Archiving"
    end
  end
end
