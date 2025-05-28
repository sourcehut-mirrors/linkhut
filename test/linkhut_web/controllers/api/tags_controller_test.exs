defmodule LinkhutWeb.Api.TagsControllerTest do
  use LinkhutWeb.ConnCase
  alias Linkhut.Repo

  alias Linkhut.{Repo, Links.Link}

  setup {LinkhutWeb.ConnCase, :register_and_set_up_api_token}

  describe "GET /_/v1/tags/get" do
    test "returns all tags as JSON", %{conn: conn, user: user} do
      insert(:link, user: user, tags: ["elixir", "phoenix"])
      insert(:link, user: user, tags: ["elixir"])

      conn = get(conn, ~p"/_/v1/tags/get")

      json = json_response(conn, 200)

      assert json["elixir"] == 2
      assert json["phoenix"] == 1
    end

    @tag accept: "application/xml"
    test "returns all tags as XML", %{conn: conn, user: user} do
      insert(:link, user: user, tags: ["elixir", "phoenix"])
      insert(:link, user: user, tags: ["elixir"])

      conn = get(conn, ~p"/_/v1/tags/get")

      assert response_content_type(conn, :xml)
      body = response(conn, 200)

      assert body == """
             <?xml version=\"1.0\" encoding=\"UTF-8\"?>
             <tags>
               <tag count=\"2\" tag=\"elixir\"/>
               <tag count=\"1\" tag=\"phoenix\"/>
             </tags>\
             """
    end
  end

  describe "GET /_/v1/tags/delete" do
    for format <- ["application/json", "application/xml"] do
      @tag scopes: "tags:write"
      @tag accept: format
      test "deletes a tag from all user's links (accept: #{format})", %{conn: conn, user: user} do
        link1 = insert(:link, user: user, tags: ["elixir", "phoenix"])
        link2 = insert(:link, user: user, tags: ["elixir"])

        conn = get(conn, ~p"/_/v1/tags/delete", %{"tag" => "elixir"})

        assert response(conn, 200) =~ "done"

        tags1 = Repo.get_by(Link, url: link1.url).tags
        tags2 = Repo.get_by(Link, url: link2.url).tags

        refute "elixir" in tags1
        refute "elixir" in tags2
        assert "phoenix" in tags1
      end
    end
  end

  describe "GET /_/v1/tags/rename" do
    for format <- ["application/json", "application/xml"] do
      @tag scopes: "tags:write"
      @tag accept: format
      test "renames a tag in all user's links (accept: #{format})", %{conn: conn, user: user} do
        link = insert(:link, user: user, tags: ["elixir", "phoenix"])

        conn =
          get(conn, ~p"/_/v1/tags/rename", %{
            "old" => "elixir",
            "new" => "elixir-lang"
          })

        assert response(conn, 200) =~ "done"

        updated = Repo.get_by(Link, url: link.url).tags
        assert "elixir-lang" in updated
        refute "elixir" in updated
        assert "phoenix" in updated
      end
    end
  end
end
