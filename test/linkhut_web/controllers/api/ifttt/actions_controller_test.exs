defmodule LinkhutWeb.Api.IFTTT.ActionsControllerTest do
  use LinkhutWeb.ConnCase

  @moduletag scopes: "ifttt"

  alias Linkhut.Links

  setup {LinkhutWeb.ConnCase, :register_and_set_up_api_token}

  defp unique_url, do: "https://example.com/#{System.unique_integer([:positive])}"

  defp assert_400_with_skip(conn, path, params) do
    {400, _headers, body} =
      assert_error_sent(400, fn ->
        conn |> post(path, params)
      end)

    assert [%{"status" => "SKIP", "message" => "missing parameters"}] =
             Jason.decode!(body)["errors"]
  end

  describe "POST /_/ifttt/v1/actions/add_public_link" do
    test "creates a new public link", %{conn: conn, user: user} do
      url = unique_url()

      body =
        conn
        |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
          "actionFields" => %{
            "url" => url,
            "title" => "New Public Link",
            "tags" => "foo bar",
            "notes" => "some notes"
          }
        })
        |> json_response(200)

      assert [%{"id" => ^url}] = body["data"]

      assert %{title: "New Public Link", is_private: false, notes: "some notes"} =
               Links.get(url, user.id)
    end

    test "appends via:ifttt to tags on creation", %{conn: conn, user: user} do
      url = unique_url()

      conn
      |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{"url" => url, "title" => "Tagged", "tags" => "foo bar"}
      })
      |> json_response(200)

      link = Links.get(url, user.id)
      assert "via:ifttt" in link.tags
      assert "foo" in link.tags
      assert "bar" in link.tags
    end

    test "appends via:ifttt when tags field is absent", %{conn: conn, user: user} do
      url = unique_url()

      conn
      |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{"url" => url, "title" => "No Tags"}
      })
      |> json_response(200)

      link = Links.get(url, user.id)
      assert "via:ifttt" in link.tags
    end

    test "does not append via:ifttt on update", %{conn: conn, user: user} do
      url = unique_url()
      {:ok, _link} = Links.create_link(user, %{"url" => url, "title" => "Original"})

      conn
      |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{"url" => url, "title" => "Updated", "tags" => "new"}
      })
      |> json_response(200)

      link = Links.get(url, user.id)
      refute "via:ifttt" in link.tags
    end

    test "updates existing link if URL already exists", %{conn: conn, user: user} do
      url = unique_url()
      {:ok, _link} = Links.create_link(user, %{"url" => url, "title" => "Original"})

      conn
      |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{"url" => url, "title" => "Updated"}
      })
      |> json_response(200)

      assert %{title: "Updated"} = Links.get(url, user.id)
    end

    test "returns correct JSON structure", %{conn: conn} do
      url = unique_url()

      body =
        conn
        |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
          "actionFields" => %{"url" => url, "title" => "Structure Test"}
        })
        |> json_response(200)

      assert [%{"id" => ^url, "url" => bookmark_url}] = body["data"]
      assert is_binary(bookmark_url)
    end

    test "returns 400 when actionFields missing", %{conn: conn} do
      assert_400_with_skip(conn, ~p"/_/ifttt/v1/actions/add_public_link", %{})
    end

    test "returns 400 when url missing from actionFields", %{conn: conn} do
      assert_400_with_skip(conn, ~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{}
      })
    end
  end

  describe "POST /_/ifttt/v1/actions/add_private_link" do
    test "creates a new private link", %{conn: conn, user: user} do
      url = unique_url()

      conn
      |> post(~p"/_/ifttt/v1/actions/add_private_link", %{
        "actionFields" => %{"url" => url, "title" => "Private Link"}
      })
      |> json_response(200)

      assert %{is_private: true} = Links.get(url, user.id)
    end

    test "updates existing link as private", %{conn: conn, user: user} do
      url = unique_url()
      {:ok, _link} = Links.create_link(user, %{"url" => url, "title" => "Original"})

      conn
      |> post(~p"/_/ifttt/v1/actions/add_private_link", %{
        "actionFields" => %{"url" => url, "title" => "Updated Private"}
      })
      |> json_response(200)

      assert %{title: "Updated Private", is_private: true} = Links.get(url, user.id)
    end

    test "returns 400 when actionFields missing", %{conn: conn} do
      assert_400_with_skip(conn, ~p"/_/ifttt/v1/actions/add_private_link", %{})
    end

    test "returns 400 when url missing from actionFields", %{conn: conn} do
      assert_400_with_skip(conn, ~p"/_/ifttt/v1/actions/add_private_link", %{
        "actionFields" => %{}
      })
    end
  end

  describe "IFTTT actions (unauthenticated)" do
    test "add_public_link returns 401 without auth" do
      unauthenticated_api_conn()
      |> post(~p"/_/ifttt/v1/actions/add_public_link", %{
        "actionFields" => %{"url" => "https://example.com", "title" => "Test"}
      })
      |> json_response(401)
    end

    test "add_private_link returns 401 without auth" do
      unauthenticated_api_conn()
      |> post(~p"/_/ifttt/v1/actions/add_private_link", %{
        "actionFields" => %{"url" => "https://example.com", "title" => "Test"}
      })
      |> json_response(401)
    end
  end
end
