defmodule LinkhutWeb.Settings.OauthControllerTest do
  use LinkhutWeb.ConnCase

  alias Linkhut.Oauth

  setup {LinkhutWeb.ConnCase, :register_and_log_in_user}

  defp create_application(user, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "name" => "Test App #{System.unique_integer([:positive])}",
          "redirect_uri" => "https://example.com/callback"
        },
        attrs
      )

    {:ok, application} = Oauth.create_application(user, params)
    application
  end

  defp create_personal_access_token(user) do
    Oauth.create_token!(user, %{
      comment: "test token",
      scopes: "posts:read posts:write tags:read tags:write"
    })
  end

  describe "unauthenticated access" do
    test "GET /_/oauth redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/oauth")
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end

    test "GET /_/oauth/personal-token redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/oauth/personal-token")
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end

    test "POST /_/oauth/personal-token redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> post(~p"/_/oauth/personal-token", %{"comment" => "test"})
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end

    test "GET /_/oauth/register redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/oauth/register")
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end

    test "POST /_/oauth/register redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> post(~p"/_/oauth/register", %{
          "application" => %{"name" => "App", "redirect_uri" => "https://example.com"}
        })
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "GET /_/oauth" do
    test "renders the oauth settings page", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ "Personal Access Tokens"
      assert response =~ "Authorized Applications"
      assert response =~ "Registered Applications"
    end

    test "shows 'Generate new token' link", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ ~s(href="/_/oauth/personal-token")
      assert response =~ "Generate new token"
    end

    test "shows 'Register new application' link", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ ~s(href="/_/oauth/register")
      assert response =~ "Register new application"
    end

    test "shows empty state when no tokens or applications exist", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ "You have not created any personal access tokens."
      assert response =~ "You have not granted any third party clients access to your account."
      assert response =~ "You have not registered any OAuth applications yet."
    end

    test "lists personal access tokens when they exist", %{conn: conn, user: user} do
      token = create_personal_access_token(user)

      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ String.slice(token.token, 0, 8)
      assert response =~ "test token"
      assert response =~ "Revoke"
    end

    test "lists registered applications when they exist", %{conn: conn, user: user} do
      application = create_application(user, %{"name" => "My Test App"})

      response =
        conn
        |> get(~p"/_/oauth")
        |> html_response(200)

      assert response =~ "My Test App"
      assert response =~ application.uid
      assert response =~ "Manage"
    end
  end

  describe "GET /_/oauth/personal-token" do
    test "renders the new personal token form", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/personal-token")
        |> html_response(200)

      assert response =~ "Personal Access Token"
      assert response =~ "Generate token"
      assert response =~ "expire in one year"
    end

    test "contains a form that posts to the personal-token endpoint", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/personal-token")
        |> html_response(200)

      assert response =~ ~s(action="/_/oauth/personal-token")
    end

    test "contains a comment input field", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/personal-token")
        |> html_response(200)

      assert response =~ "comment"
    end
  end

  describe "POST /_/oauth/personal-token" do
    test "creates a token and displays it", %{conn: conn} do
      response =
        conn
        |> post(~p"/_/oauth/personal-token", %{"comment" => "my api token"})
        |> html_response(200)

      assert response =~ "Personal Access Token"
      assert response =~ "will never be shown to you again"
      assert response =~ "Continue"
    end

    test "shows a continue link back to oauth settings", %{conn: conn} do
      response =
        conn
        |> post(~p"/_/oauth/personal-token", %{"comment" => "test"})
        |> html_response(200)

      assert response =~ ~s(href="/_/oauth")
    end
  end

  describe "GET /_/oauth/personal-token/revoke/:id" do
    test "renders the revoke confirmation page", %{conn: conn, user: user} do
      token = create_personal_access_token(user)

      response =
        conn
        |> get(~p"/_/oauth/personal-token/revoke/#{token.id}")
        |> html_response(200)

      assert response =~ "Are you sure?"
      assert response =~ "revoke personal access token"
      assert response =~ String.slice(token.token, 0, 8)
      assert response =~ "Revoke"
    end

    test "contains a form to confirm revocation", %{conn: conn, user: user} do
      token = create_personal_access_token(user)

      response =
        conn
        |> get(~p"/_/oauth/personal-token/revoke/#{token.id}")
        |> html_response(200)

      assert response =~ ~s(action="/_/oauth/personal-token/revoke/#{token.id}")
    end
  end

  describe "PUT /_/oauth/personal-token/revoke/:id" do
    test "revokes the token and redirects to oauth settings", %{conn: conn, user: user} do
      token = create_personal_access_token(user)

      conn =
        conn
        |> put(~p"/_/oauth/personal-token/revoke/#{token.id}", %{
          "access_token" => %{"id" => to_string(token.id)}
        })

      assert redirected_to(conn) == ~p"/_/oauth"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Revoked token"
    end
  end

  describe "GET /_/oauth/register" do
    test "renders the register application form", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/register")
        |> html_response(200)

      assert response =~ "Register OAuth application"
      assert response =~ "Register"
    end

    test "contains a form that posts to the register endpoint", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/register")
        |> html_response(200)

      assert response =~ ~s(action="/_/oauth/register")
    end

    test "contains name and redirect_uri fields", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/register")
        |> html_response(200)

      assert response =~ "name"
      assert response =~ "redirect_uri"
    end

    test "links to API documentation", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/register")
        |> html_response(200)

      assert response =~ "API docs"
      assert response =~ "docs.linkhut.org"
    end
  end

  describe "POST /_/oauth/register" do
    test "creates an application and shows credentials", %{conn: conn} do
      response =
        conn
        |> post(~p"/_/oauth/register", %{
          "application" => %{
            "name" => "Brand New App",
            "redirect_uri" => "https://example.com/callback"
          }
        })
        |> html_response(200)

      assert response =~ "OAuth application registered"
      assert response =~ "Application ID"
      assert response =~ "Application Secret"
      assert response =~ "will never be shown to you again"
      assert response =~ "Continue"
    end

    test "re-renders form with errors on invalid data", %{conn: conn} do
      response =
        conn
        |> post(~p"/_/oauth/register", %{
          "application" => %{
            "name" => "",
            "redirect_uri" => ""
          }
        })
        |> html_response(200)

      assert response =~ "Register OAuth application"
    end
  end

  describe "GET /_/oauth/application/:uid/settings" do
    test "renders the edit application form", %{conn: conn, user: user} do
      application = create_application(user, %{"name" => "Editable App"})

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ "OAuth application settings"
      assert response =~ "Update"
    end

    test "contains a form that submits to the application settings endpoint", %{
      conn: conn,
      user: user
    } do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ ~s(action="/_/oauth/application/#{application.uid}/settings")
    end

    test "contains name and redirect_uri fields", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ "name"
      assert response =~ "redirect_uri"
    end

    test "shows reset secret section", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ "Reset application secret"
    end

    test "shows revoke all tokens section", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ "Revoke all tokens"
    end

    test "shows delete application section", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/application/#{application.uid}/settings")
        |> html_response(200)

      assert response =~ "Delete application"
      assert response =~ "Delete"
    end
  end

  describe "PUT /_/oauth/application/:uid/settings" do
    test "updates the application and redirects", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> put(~p"/_/oauth/application/#{application.uid}/settings", %{
          "application" => %{
            "name" => "Updated App Name",
            "redirect_uri" => "https://updated.example.com/callback"
          }
        })

      assert redirected_to(conn) == ~p"/_/oauth"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Application updated"
    end

    test "re-renders form with errors on invalid data", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> put(~p"/_/oauth/application/#{application.uid}/settings", %{
          "application" => %{
            "name" => "",
            "redirect_uri" => ""
          }
        })
        |> html_response(200)

      assert response =~ "OAuth application settings"
    end
  end

  describe "POST /_/oauth/application/delete/:uid" do
    test "deletes the application and redirects", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> post(~p"/_/oauth/application/delete/#{application.uid}")

      assert redirected_to(conn) == ~p"/_/oauth"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Application deleted"
    end
  end

  describe "POST /_/oauth/reset-secret/:uid" do
    test "resets the application secret and shows new credentials", %{conn: conn, user: user} do
      application = create_application(user)
      old_secret = application.secret

      response =
        conn
        |> post(~p"/_/oauth/reset-secret/#{application.uid}")
        |> html_response(200)

      assert response =~ "Application secret reset"
      assert response =~ "Application ID"
      assert response =~ "Application Secret"
      refute response =~ old_secret
    end
  end

  describe "POST /_/oauth/revoke-tokens/:uid" do
    test "revokes all tokens and redirects to application settings", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> post(~p"/_/oauth/revoke-tokens/#{application.uid}")

      assert redirected_to(conn) == "/_/oauth/application/#{application.uid}/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "tokens"
    end
  end

  describe "GET /_/oauth/authorize" do
    test "renders the authorization page for a valid application", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/authorize", %{
          "client_id" => application.uid,
          "redirect_uri" => "https://example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read"
        })
        |> html_response(200)

      assert response =~ "Authorize account access"
      assert response =~ application.name
      assert response =~ "Proceed and grant access"
      assert response =~ "Cancel and do not grant access"
    end

    test "shows requested scopes", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/authorize", %{
          "client_id" => application.uid,
          "redirect_uri" => "https://example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read tags:write"
        })
        |> html_response(200)

      assert response =~ "posts:read"
      assert response =~ "tags:write"
    end

    test "renders error for invalid client_id", %{conn: conn} do
      response =
        conn
        |> get(~p"/_/oauth/authorize", %{
          "client_id" => "invalid",
          "redirect_uri" => "https://example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read"
        })
        |> html_response(422)

      assert response =~ "An error occured"
    end

    test "renders error for mismatched redirect_uri", %{conn: conn, user: user} do
      application = create_application(user)

      response =
        conn
        |> get(~p"/_/oauth/authorize", %{
          "client_id" => application.uid,
          "redirect_uri" => "https://wrong.example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read"
        })
        |> html_response(422)

      assert response =~ "An error occured"
    end

    test "unauthenticated access redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> get(~p"/_/oauth/authorize", %{
          "client_id" => "anything",
          "response_type" => "code"
        })
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "POST /_/oauth/authorize" do
    test "grants access and redirects to the application", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> post(~p"/_/oauth/authorize", %{
          "client_id" => application.uid,
          "redirect_uri" => "https://example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read"
        })

      assert redirected_to(conn) =~ "https://example.com/callback"
      assert redirected_to(conn) =~ "code="
    end

    test "unauthenticated access redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> post(~p"/_/oauth/authorize", %{
          "client_id" => "anything",
          "response_type" => "code"
        })
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "DELETE /_/oauth/authorize" do
    test "denies access and redirects to the application with error", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> delete(~p"/_/oauth/authorize", %{
          "client_id" => application.uid,
          "redirect_uri" => "https://example.com/callback",
          "response_type" => "code",
          "scope" => "posts:read"
        })

      assert redirected_to(conn) =~ "https://example.com/callback"
      assert redirected_to(conn) =~ "error=access_denied"
    end

    test "unauthenticated access redirects to login page" do
      conn = build_conn()

      redirect_path =
        conn
        |> delete(~p"/_/oauth/authorize", %{
          "client_id" => "anything",
          "response_type" => "code"
        })
        |> redirected_to(302)

      assert redirect_path == "/_/login"
    end
  end

  describe "POST /_/oauth/revoke-access/:uid" do
    test "revokes access and redirects to oauth settings", %{conn: conn, user: user} do
      application = create_application(user)

      conn =
        conn
        |> post(~p"/_/oauth/revoke-access/#{application.uid}")

      assert redirected_to(conn) == ~p"/_/oauth"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Revoked access"
    end
  end
end
