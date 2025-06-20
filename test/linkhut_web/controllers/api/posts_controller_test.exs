defmodule LinkhutWeb.Api.PostsControllerTest do
  use LinkhutWeb.ConnCase
  alias Linkhut.{Repo, Links.Link}
  import Linkhut.AccountsFixtures

  setup {LinkhutWeb.ConnCase, :register_and_set_up_api_token}

  describe "GET /_/v1/posts/update" do
    test "fails when unauthenticated [JSON]", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.delete_req_header("authorization")
        |> get("/_/v1/posts/update")

      assert json_response(conn, 401) == %{"errors" => [%{"message" => "Unauthenticated"}]}
    end

    @tag accept: "application/xml"
    test "returns epoch when no bookmarks [XML]", %{conn: conn} do
      conn = get(conn, "/_/v1/posts/update")

      assert response(conn, 200) =~
               "<update code=\"done\" time=\"1970-01-01T00:00:00Z\" inboxnew=\"\"/>"
    end

    test "returns epoch when no bookmarks [JSON]", %{conn: conn} do
      conn = get(conn, "/_/v1/posts/update")

      assert json_response(conn, 200) == %{"update_time" => "1970-01-01T00:00:00Z"}
    end

    test "returns date of last bookmark saved [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user_id: user.id)

      conn = get(conn, "/_/v1/posts/update")

      assert json_response(conn, 200) == %{"update_time" => DateTime.to_iso8601(link.inserted_at)}
    end
  end

  describe "GET /_/v1/posts/recent" do
    setup %{user: user} = context do
      link = insert(:link, user: user, title: "Recent Link", notes: "A very recent link")

      context
      |> Map.put(:link, link)
    end

    @tag accept: "application/xml"
    test "returns recent links [XML]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/recent")

      assert response(conn, 200) =~ "<post extended=\"A very recent link\""
    end

    @tag accept: "application/xml"
    test "returns recent links with invalid parameters [XML]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/recent", %{"count" => "oops"})

      assert response(conn, 200) =~ "<post extended=\"A very recent link\""
    end

    for count <- 1..10 do
      @tag accept: "application/xml"
      test "returns up to #{count} recent links [XML]", %{conn: conn} do
        conn =
          conn
          |> get("/_/v1/posts/recent", %{"count" => "1"})

        assert response(conn, 200) =~ "<post extended=\"A very recent link\""
      end

      @tag accept: "application/json"
      test "returns up to #{count} recent links [JSON]", %{link: link, conn: conn} do
        conn =
          conn
          |> get("/_/v1/posts/recent", %{"count" => "1"})

        assert json = json_response(conn, 200)
        assert post = json["posts"] |> Enum.at(0)
        assert post["description"] == link.title
        assert post["href"] == link.url
        assert post["extended"] == link.notes
      end
    end
  end

  describe "GET /_/v1/posts/add" do
    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "creates a new link [XML]", %{user: user, conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Example",
          "extended" => "A note",
          "tags" => "elixir,phoenix",
          "shared" => "yes",
          "toread" => "no"
        })

      assert response(conn, 200) =~ "<result code=\"done\"/>"
      assert Repo.get_by(Link, url: "http://example.com", user_id: user.id)
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "creates a new link [JSON]", %{user: user, conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Example",
          "extended" => "A note",
          "tags" => "elixir,phoenix",
          "shared" => "yes",
          "toread" => "no"
        })

      assert json_response(conn, 200) == %{"result_code" => "done"}
      assert Repo.get_by(Link, url: "http://example.com", user_id: user.id)
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "creates a new private link [JSON]", %{user: user, conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Example",
          "extended" => "A note",
          "tags" => "elixir,phoenix",
          "shared" => "no",
          "toread" => "no"
        })

      assert json_response(conn, 200) == %{"result_code" => "done"}
      assert Repo.get_by(Link, url: "http://example.com", user_id: user.id).is_private
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "creates a new unread link [JSON]", %{user: user, conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Example",
          "extended" => "A note",
          "tags" => "elixir,phoenix",
          "shared" => "yes",
          "toread" => "yes"
        })

      assert json_response(conn, 200) == %{"result_code" => "done"}
      assert Repo.get_by(Link, url: "http://example.com", user_id: user.id).is_unread
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "creates a new link with date [JSON]", %{user: user, conn: conn} do
      inserted_at = DateTime.add(DateTime.utc_now(:second), 5, :minute)

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Example",
          "extended" => "A note",
          "tags" => "elixir,phoenix",
          "shared" => "yes",
          "toread" => "no",
          "dt" => inserted_at |> DateTime.to_iso8601()
        })

      assert json_response(conn, 200) == %{"result_code" => "done"}

      assert Repo.get_by(Link, url: "http://example.com", user_id: user.id).inserted_at ==
               inserted_at
    end

    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "updates a link with replace=yes [XML]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Updated Title",
          "replace" => "yes"
        })

      assert response(conn, 200) =~ "<result code=\"done\"/>"
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title == "Updated Title"
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "updates a link with replace=yes [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Updated Title",
          "replace" => "yes"
        })

      assert json_response(conn, 200) == %{"result_code" => "done"}
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title == "Updated Title"
    end

    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "fails to update existing link with replace=no [XML]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Updated Title",
          "replace" => "no"
        })

      assert response(conn, 200) =~ "<result code=\"something went wrong\"/>"
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title != "Updated Title"
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "fails to update existing link with replace=no [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => "Updated Title",
          "replace" => "no"
        })

      assert json_response(conn, 200) == %{"result_code" => "something went wrong"}
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title != "Updated Title"
    end

    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "fails to update existing link with invalid data [XML]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => Enum.reduce(1..1_000, "", fn _, acc -> acc <> "." end),
          "replace" => "yes"
        })

      assert response(conn, 200) =~ "<result code=\"something went wrong\"/>"
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title != "Updated Title"
    end

    @tag scopes: "posts:write"
    @tag accept: "application/json"
    test "fails to update existing link with invalid data [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/add", %{
          "url" => "http://example.com",
          "description" => Enum.reduce(1..1_000, "", fn _, acc -> acc <> "." end),
          "replace" => "yes"
        })

      assert json_response(conn, 200) == %{"result_code" => "something went wrong"}
      assert Repo.get_by!(Link, url: link.url, user_id: user.id).title != "Updated Title"
    end
  end

  describe "GET /_/v1/posts/get" do
    @tag scopes: "posts:read"
    @tag accept: "application/xml"
    test "gets link by url [XML]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/get", %{"url" => link.url})

      assert response(conn, 200) =~ "href=\"http://example.com\""
    end

    @tag accept: "application/xml"
    test "gets link by url and include hash of metadata [XML]", %{user: user, conn: conn} do
      link = insert(:link, user: user, url: "http://example.com")

      conn =
        conn
        |> get("/_/v1/posts/get", %{"url" => link.url, "meta" => "yes"})

      assert response(conn, 200) =~
               "meta=\"#{:crypto.hash(:md5, link.updated_at |> DateTime.to_iso8601()) |> Base.encode16(case: :lower)}\""
    end

    @tag accept: "application/xml"
    test "404 response when getting non-existing link by url [XML]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/get", %{"url" => "http://does-not-exist.example.com"})

      assert response(conn, 404) =~ "<result code=\"something went wrong\"/>"
    end

    test "404 response when getting non-existing link by url [JSON]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/get", %{"url" => "http://does-not-exist.example.com"})

      assert json_response(conn, 404) == %{"result_code" => "something went wrong"}
    end

    @tag scopes: "posts:read"
    @tag accept: "application/xml"
    test "gets links by date [XML]", %{user: user, conn: conn} do
      {:ok, datetime, 0} = DateTime.from_iso8601("2024-01-01T23:00:00Z")
      _ = insert(:link, user: user, url: "http://example.com", inserted_at: datetime)

      conn =
        conn
        |> get("/_/v1/posts/get", %{"dt" => "2024-01-01"})

      assert response(conn, 200) =~ "href=\"http://example.com\""
    end

    test "when no arguments, returns the posts matching the date of the most recent bookmark [JSON]",
         %{user: user, conn: conn} do
      link = insert(:link, user_id: user.id)
      md5 = :crypto.hash(:md5, link.url) |> Base.encode16(case: :lower)

      conn = get(conn, "/_/v1/posts/get")

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

    @tag accept: "application/xml"
    test "get by hash [XML]", %{user: user, conn: conn} do
      link = insert(:link, user_id: user.id)
      md5 = :crypto.hash(:md5, link.url) |> Base.encode16(case: :lower)

      conn = get(conn, "/_/v1/posts/get", %{"hashes" => md5})

      assert response(conn, 200) =~ "href=\"#{link.url}\""
    end

    test "get by hash [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user_id: user.id)
      md5 = :crypto.hash(:md5, link.url) |> Base.encode16(case: :lower)

      conn = get(conn, "/_/v1/posts/get", %{"hashes" => md5})

      assert json_response(conn, 200)["posts"] |> Enum.map(& &1["href"]) == [link.url]
    end

    test "get by tag [JSON]", %{user: user, conn: conn} do
      link = insert(:link, user_id: user.id, tags: ["foo"])

      conn = get(conn, "/_/v1/posts/get", %{"tag" => "foo"})

      assert json_response(conn, 200)["posts"] |> Enum.map(& &1["href"]) == [link.url]
    end
  end

  describe "GET /_/v1/posts/suggest" do
    setup %{user: user} = context do
      insert(:link, user: user_fixture(), url: "http://elixir-lang.org", tags: ["programming"])
      insert(:link, user: user, url: "http://elixir-lang.org", tags: ["elixir"])
      context
    end

    @tag accept: "application/xml"
    test "suggested tags for a URL [XML]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/suggest", %{"url" => "http://elixir-lang.org"})

      assert response(conn, 200) == """
             <?xml version=\"1.0\" encoding=\"UTF-8\"?>
             <suggest>
               <popular>programming</popular>
               <recommended>elixir</recommended>
             </suggest>\
             """
    end

    test "suggested tags for a URL [JSON]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/suggest", %{"url" => "http://elixir-lang.org"})

      assert json_response(conn, 200) == [
               %{"popular" => ["programming"]},
               %{"recommended" => ["elixir"]}
             ]
    end
  end

  describe "GET /_/v1/posts/delete" do
    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "deletes a link by URL [XML]", %{user: user, conn: conn} do
      _ = insert(:link, user: user, url: "http://delete-me.example.com")

      conn =
        conn
        |> get("/_/v1/posts/delete", %{"url" => "http://delete-me.example.com"})

      assert response(conn, 200) =~ "<result code=\"done\"/>"
      assert Repo.all(Link) == []
    end

    @tag scopes: "posts:write"
    @tag accept: "application/xml"
    test "deletes non-existing link by URL [XML]", %{conn: conn} do
      conn =
        conn
        |> get("/_/v1/posts/delete", %{"url" => "http://does-not-exist.example.com"})

      assert response(conn, 200) =~ "<result code=\"something went wrong\"/>"
    end
  end

  describe "GET /_/v1/posts/dates" do
    setup %{user: user} do
      Enum.each(
        ["2023-01-01T23:00:00Z", "2024-01-01T23:00:00Z", "2025-01-01T23:00:00Z"],
        fn date ->
          {:ok, datetime, 0} = DateTime.from_iso8601(date)
          _ = insert(:link, user: user, url: "http://#{date}.example.com", inserted_at: datetime)
        end
      )
    end

    @tag accept: "application/xml"
    test "returns dates with number of posts at each date [XML]", %{user: user, conn: conn} do
      conn = get(conn, "/_/v1/posts/dates")

      assert response(conn, 200) == """
             <?xml version=\"1.0\" encoding=\"UTF-8\"?>
             <dates tag=\"\" user=\"#{user.username}\">
               <date count=\"1\" date=\"2025-01-01\"/>
               <date count=\"1\" date=\"2024-01-01\"/>
               <date count=\"1\" date=\"2023-01-01\"/>
             </dates>\
             """
    end

    test "returns dates with number of posts at each date [JSON]", %{conn: conn} do
      conn = get(conn, "/_/v1/posts/dates")

      assert json_response(conn, 200) == %{
               "dates" => %{"2023-01-01" => 1, "2024-01-01" => 1, "2025-01-01" => 1}
             }
    end
  end

  describe "GET /_/v1/posts/all" do
    setup %{user: user} = context do
      other_user = user_fixture()

      # These links belong to the logged-in user
      link1 =
        insert(:link,
          user: user,
          url: "http://one.example.com",
          title: "One",
          inserted_at: DateTime.utc_now() |> DateTime.add(-30, :second)
        )

      link2 = insert(:link, user: user, url: "http://two.example.com", title: "Two")

      # This link belongs to another user and should not be included
      _ = insert(:link, user: other_user, url: "http://three.example.com", title: "Three")

      context
      |> Map.put(:links, [link2, link1])
    end

    @tag accept: "application/xml"
    test "returns all links [XML]", %{links: [new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all")
      assert response(conn, 200) =~ "href=\"#{new.url}\""
      assert response(conn, 200) =~ "href=\"#{old.url}\""
    end

    test "returns all links [JSON]", %{links: [new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all")
      assert json_response(conn, 200) |> Enum.map(& &1["href"]) == [new.url, old.url]
    end

    @tag accept: "application/xml"
    test "returns all hashes [XML]", %{links: [new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all", %{"hashes" => "yes"})

      assert response(conn, 200) =~ """
               <post meta=\"#{:crypto.hash(:md5, new.updated_at |> DateTime.to_iso8601()) |> Base.encode16(case: :lower)}\" url=\"#{:crypto.hash(:md5, new.url) |> Base.encode16(case: :lower)}\"/>
               <post meta=\"#{:crypto.hash(:md5, old.updated_at |> DateTime.to_iso8601()) |> Base.encode16(case: :lower)}\" url=\"#{:crypto.hash(:md5, old.url) |> Base.encode16(case: :lower)}\"/>
             """
    end

    test "returns all hashes [JSON]", %{links: [new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all", %{"hashes" => "yes"})

      assert json_response(conn, 200) |> Enum.map(& &1["url"]) == [
               :crypto.hash(:md5, new.url) |> Base.encode16(case: :lower),
               :crypto.hash(:md5, old.url) |> Base.encode16(case: :lower)
             ]
    end

    test "returns all links created within the last 10 seconds [JSON]", %{
      links: [new, _old],
      conn: conn
    } do
      conn =
        get(conn, "/_/v1/posts/all", %{
          "fromdt" => DateTime.add(DateTime.utc_now(), -10, :second) |> DateTime.to_iso8601(),
          "todt" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert json_response(conn, 200) |> Enum.map(& &1["href"]) == [new.url]
    end

    for count <- ["5", "10", "0", "oops"] do
      @tag count: count
      test "returns all links (count: #{count}) [JSON]", %{
        links: [new, old],
        conn: conn,
        count: count
      } do
        conn = get(conn, "/_/v1/posts/all", %{"results" => count})
        assert json_response(conn, 200) |> Enum.map(& &1["href"]) == [new.url, old.url]
      end
    end

    test "returns all links with start offset [JSON]", %{links: [_new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all", %{"start" => "1"})
      assert json_response(conn, 200) |> Enum.map(& &1["href"]) == [old.url]
    end

    test "returns all links with (invalid offset) [JSON]", %{links: [new, old], conn: conn} do
      conn = get(conn, "/_/v1/posts/all", %{"start" => "oops"})
      assert json_response(conn, 200) |> Enum.map(& &1["href"]) == [new.url, old.url]
    end
  end
end
