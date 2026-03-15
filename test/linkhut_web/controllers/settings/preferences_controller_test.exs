defmodule LinkhutWeb.Settings.PreferencesControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Accounts.Preferences

  setup {LinkhutWeb.ConnCase, :register_and_log_in_user}

  describe "GET /_/preferences" do
    test "renders preferences form", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/preferences")
        |> html_response(200)

      assert response =~ "Show full URL"
      assert response =~ "Show exact dates"
      assert response =~ "Make new bookmarks private"
      assert response =~ "Strip tracking parameters"
      assert response =~ "Timezone"
    end

    test "redirects if not logged in" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/preferences")
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "POST /_/preferences (first save)" do
    test "creates preferences on first save", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/_/preferences", %{
          "user_preference" => %{
            "show_exact_dates" => "true",
            "show_url" => "false"
          }
        })

      assert redirected_to(conn) == ~p"/_/preferences"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Preferences updated"

      pref = Preferences.get_or_default(user)
      assert pref.show_exact_dates == true
      assert pref.show_url == false
    end

    test "rejects invalid timezone", %{conn: conn} do
      response =
        conn
        |> post(~p"/_/preferences", %{
          "user_preference" => %{
            "timezone" => "Bad/Zone"
          }
        })
        |> html_response(200)

      assert response =~ "is not a valid timezone"
    end
  end

  describe "PUT /_/preferences (subsequent saves)" do
    test "updates existing preferences", %{conn: conn, user: user} do
      Preferences.upsert(user, %{show_url: false})

      conn =
        put(conn, ~p"/_/preferences", %{
          "user_preference" => %{
            "show_url" => "true",
            "default_private" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/_/preferences"

      pref = Preferences.get_or_default(user)
      assert pref.show_url == true
      assert pref.default_private == true
    end

    test "toggles a boolean from true back to false", %{conn: conn, user: user} do
      Preferences.upsert(user, %{show_exact_dates: true})

      conn =
        put(conn, ~p"/_/preferences", %{
          "user_preference" => %{
            "show_exact_dates" => "false"
          }
        })

      assert redirected_to(conn) == ~p"/_/preferences"

      pref = Preferences.get_or_default(user)
      assert pref.show_exact_dates == false
    end

    test "sets timezone", %{conn: conn, user: user} do
      Preferences.upsert(user, %{})

      conn =
        put(conn, ~p"/_/preferences", %{
          "user_preference" => %{
            "timezone" => "America/Chicago"
          }
        })

      assert redirected_to(conn) == ~p"/_/preferences"

      pref = Preferences.get_or_default(user)
      assert pref.timezone == "America/Chicago"
    end
  end
end
