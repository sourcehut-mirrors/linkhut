defmodule LinkhutWeb.Api.IFTTT.TriggersControllerTest do
  use LinkhutWeb.ConnCase

  @moduletag scopes: "ifttt"

  alias Linkhut.Links

  setup {LinkhutWeb.ConnCase, :register_and_set_up_api_token}

  defp unique_url, do: "https://example.com/#{System.unique_integer([:positive])}"

  defp create_link(user, attrs) do
    params =
      Map.merge(
        %{
          "url" => unique_url(),
          "title" => "Test Link",
          "tags" => "",
          "notes" => ""
        },
        attrs
      )

    assert {:ok, link} = Links.create_link(user, params)
    link
  end

  defp assert_400_with_skip(conn, params) do
    {400, _headers, body} =
      assert_error_sent(400, fn ->
        conn |> post(~p"/_/ifttt/v1/triggers/new_public_link_tagged", params)
      end)

    assert [%{"status" => "SKIP", "message" => "missing parameters"}] =
             Jason.decode!(body)["errors"]
  end

  describe "POST /_/ifttt/v1/triggers/new_public_link" do
    test "returns empty data when no links exist", %{conn: conn} do
      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      assert body["data"] == []
    end

    test "returns public non-unread links", %{conn: conn, user: user} do
      link = create_link(user, %{"title" => "Public Link"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      assert [%{"url" => url, "title" => "Public Link"}] = body["data"]
      assert url == link.url
    end

    test "excludes private links", %{conn: conn, user: user} do
      create_link(user, %{"is_private" => "true", "title" => "Private"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      assert body["data"] == []
    end

    test "excludes unread links", %{conn: conn, user: user} do
      create_link(user, %{"is_unread" => "true", "title" => "Unread"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      assert body["data"] == []
    end

    test "respects limit parameter", %{conn: conn, user: user} do
      create_link(user, %{"title" => "Link 1"})
      create_link(user, %{"title" => "Link 2"})
      create_link(user, %{"title" => "Link 3"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link", %{"limit" => 1})
        |> json_response(200)

      assert length(body["data"]) == 1
    end

    test "returns correct JSON structure", %{conn: conn, user: user} do
      create_link(user, %{"title" => "Structured", "tags" => "foo bar", "notes" => "some notes"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      [link] = body["data"]
      assert is_binary(link["time"])
      assert is_binary(link["url"])
      assert is_binary(link["tags"])
      assert link["notes"] == "some notes"
      assert link["title"] == "Structured"
      assert is_binary(link["meta"]["id"])
      assert is_integer(link["meta"]["timestamp"])
    end

    test "only returns own links", %{conn: conn} do
      other_user = Linkhut.AccountsFixtures.user_fixture()
      create_link(other_user, %{"title" => "Other User Link"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link")
        |> json_response(200)

      assert body["data"] == []
    end
  end

  describe "POST /_/ifttt/v1/triggers/new_public_link_tagged" do
    test "returns links filtered by tag", %{conn: conn, user: user} do
      create_link(user, %{"title" => "Tagged", "tags" => "elixir"})
      create_link(user, %{"title" => "Untagged", "tags" => "python"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link_tagged", %{
          "triggerFields" => %{"tag" => "elixir"}
        })
        |> json_response(200)

      assert [%{"title" => "Tagged"}] = body["data"]
    end

    test "returns empty data when no links match tag", %{conn: conn, user: user} do
      create_link(user, %{"title" => "No Match", "tags" => "rust"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link_tagged", %{
          "triggerFields" => %{"tag" => "elixir"}
        })
        |> json_response(200)

      assert body["data"] == []
    end

    test "returns 400 when triggerFields missing", %{conn: conn} do
      assert_400_with_skip(conn, %{})
    end

    test "returns 400 when tag is empty string", %{conn: conn} do
      assert_400_with_skip(conn, %{"triggerFields" => %{"tag" => ""}})
    end

    test "returns 400 when tag key is missing", %{conn: conn} do
      assert_400_with_skip(conn, %{"triggerFields" => %{}})
    end

    test "respects limit parameter", %{conn: conn, user: user} do
      create_link(user, %{"title" => "Tagged 1", "tags" => "elixir"})
      create_link(user, %{"title" => "Tagged 2", "tags" => "elixir"})

      body =
        conn
        |> post(~p"/_/ifttt/v1/triggers/new_public_link_tagged", %{
          "triggerFields" => %{"tag" => "elixir"},
          "limit" => 1
        })
        |> json_response(200)

      assert length(body["data"]) == 1
    end
  end

  describe "POST /_/ifttt/v1/triggers/new_public_link (unauthenticated)" do
    test "returns 401 without auth" do
      unauthenticated_api_conn()
      |> post(~p"/_/ifttt/v1/triggers/new_public_link")
      |> json_response(401)
    end
  end
end
