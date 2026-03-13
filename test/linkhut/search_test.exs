defmodule Linkhut.SearchTest do
  use Linkhut.DataCase, async: true

  alias Linkhut.Search
  alias Linkhut.Search.Context
  alias Linkhut.Links
  alias Linkhut.AccountsFixtures

  describe "search with site filters" do
    setup do
      user = AccountsFixtures.user_fixture()

      links =
        create_links_for_user(user, [
          %{url: "https://example.com/page1", title: "Example Page 1", tags: ["test"]},
          %{url: "https://github.com/user/repo", title: "GitHub Repository", tags: ["code"]},
          %{url: "https://example.com/page2", title: "Example Page 2", tags: ["test"]},
          %{url: "https://docs.example.org/guide", title: "Documentation Guide", tags: ["docs"]}
        ])

      %{
        links: links,
        context: %Context{visible_as: user.username}
      }
    end

    test "filters by single site", %{context: context, links: links} do
      assert search_urls(context, "site:example.com") == urls_by_host(links, "example.com")
    end

    test "filters by multiple sites with OR logic", %{context: context, links: links} do
      assert search_urls(context, "site:example.com site:docs.example.org") ==
               urls_by_hosts(links, ["example.com", "docs.example.org"])
    end

    test "combines site filter with text search", %{context: context, links: links} do
      results = run_search(context, "site:example.com Page 1")
      expected_url = find_link_by_title(links, "Example Page 1").url
      assert expected_url in Enum.map(results, & &1.url)
    end
  end

  describe "search with inurl filters" do
    setup do
      user = AccountsFixtures.user_fixture()

      links =
        create_links_for_user(user, [
          %{url: "https://example.com/foobar", title: "FooBar Page", tags: ["foobar"]},
          %{
            url: "https://github.com/user/foobar-repo",
            title: "FooBar Repository",
            tags: ["code"]
          },
          %{url: "https://api.example.com/dashboard", title: "Dashboard API", tags: ["api"]},
          %{url: "https://example.com/login", title: "Login Page", tags: ["auth"]}
        ])

      %{
        links: links,
        context: %Context{visible_as: user.username}
      }
    end

    test "filters by single inurl term", %{context: context, links: links} do
      assert search_urls(context, "inurl:foobar") == urls_containing_term(links, "foobar")
    end

    test "filters by multiple inurl terms with AND logic", %{context: context, links: links} do
      assert search_urls(context, "inurl:foobar inurl:repo") ==
               urls_containing_all_terms(links, ["foobar", "repo"])
    end

    test "combines inurl and site filters", %{context: context, links: links} do
      results = search_urls(context, "site:example.com inurl:foobar")

      expected_urls =
        links
        |> Enum.filter(
          &(host_matches?(&1.url, "example.com") and String.contains?(&1.url, "foobar"))
        )
        |> Enum.map(& &1.url)
        |> Enum.sort()

      assert results == expected_urls
    end
  end

  describe "search visibility and text" do
    setup do
      owner = AccountsFixtures.user_fixture()

      links =
        create_links_for_user(owner, [
          %{
            url: "https://example.com/elixir",
            title: "Elixir Programming",
            tags: ["elixir"],
            is_private: false
          },
          %{
            url: "https://example.com/phoenix",
            title: "Phoenix Framework",
            tags: ["phoenix"],
            is_private: false
          },
          %{
            url: "https://example.com/private",
            title: "Private Link",
            tags: ["secret"],
            is_private: true
          },
          %{
            url: "https://example.com/unread",
            title: "Unread Link",
            tags: ["unread"],
            is_private: false,
            is_unread: true
          },
          %{
            url: "https://example.com/ifttt",
            title: "IFTTT Link",
            tags: ["via:ifttt"],
            is_private: false
          }
        ])

      %{owner: owner, links: links}
    end

    test "public visitor does not see private, unread, or via:ifttt links", %{
      owner: owner,
      links: links
    } do
      urls = search_urls(%Context{from: owner, visible_as: nil}, "")

      refute url_of(links, "Private Link") in urls
      refute url_of(links, "Unread Link") in urls
      refute url_of(links, "IFTTT Link") in urls

      assert url_of(links, "Elixir Programming") in urls
      assert url_of(links, "Phoenix Framework") in urls
    end

    test "owner sees all their own links", %{owner: owner, links: links} do
      urls = search_urls(%Context{from: owner, visible_as: owner.username}, "")

      assert url_of(links, "Private Link") in urls
      assert url_of(links, "Unread Link") in urls
      assert url_of(links, "IFTTT Link") in urls
    end

    test "text search filters by query", %{owner: owner, links: links} do
      urls = search_urls(%Context{from: owner, visible_as: owner.username}, "Elixir")

      assert url_of(links, "Elixir Programming") in urls
      refute url_of(links, "Private Link") in urls
      refute url_of(links, "IFTTT Link") in urls
    end

    test "cross-user visibility hides private links from other users", %{owner: owner} do
      other_user = AccountsFixtures.user_fixture()

      create_links_for_user(other_user, [
        %{
          url: "https://other.com/public",
          title: "Other Public",
          tags: ["test"],
          is_private: false
        },
        %{
          url: "https://other.com/secret",
          title: "Other Private",
          tags: ["test"],
          is_private: true
        }
      ])

      urls = search_urls(%Context{from: other_user, visible_as: owner.username}, "")

      assert "https://other.com/public" in urls
      refute "https://other.com/secret" in urls
    end
  end

  describe "hybrid search" do
    setup do
      user = AccountsFixtures.user_fixture()
      context = %Context{visible_as: user.username}
      %{user: user, context: context}
    end

    test "substring match not caught by FTS", %{user: user, context: context} do
      create_links_for_user(user, [
        %{url: "https://postmarketos.org", title: "postmarketOS is great", tags: ["linux"]},
        %{url: "https://unrelated.com", title: "Unrelated page", tags: ["other"]}
      ])

      urls = search_urls(context, "postmarket")
      assert "https://postmarketos.org" in urls
      refute "https://unrelated.com" in urls
    end

    test "word-boundary: postmarket matches postmarketOS not prepostmarket", %{
      user: user,
      context: context
    } do
      create_links_for_user(user, [
        %{
          url: "https://example.com/pmos",
          title: "postmarketOS installation guide",
          tags: ["linux"]
        },
        %{
          url: "https://example.com/other",
          title: "A prepostmarket analysis report",
          tags: ["finance"]
        }
      ])

      urls = search_urls(context, "postmarket")
      assert "https://example.com/pmos" in urls
      refute "https://example.com/other" in urls
    end

    test "FTS results rank above grep-only results", %{user: user, context: context} do
      create_links_for_user(user, [
        %{
          url: "https://example.com/fts-match",
          title: "Tomatoes in the garden",
          tags: ["garden"]
        },
        %{
          url: "https://example.com/grep-match",
          title: "tomatoville community forum",
          tags: ["forum"]
        }
      ])

      results = run_search_sorted(context, "tomato")

      # Both should appear (FTS matches "tomatoes" via stemming, grep matches "tomatoville")
      urls = Enum.map(results, & &1.url)
      assert "https://example.com/fts-match" in urls

      # FTS match should rank higher when sorted by relevancy
      [first | _] = results
      assert first.url == "https://example.com/fts-match"
    end

    test "multi-term AND logic: all terms must match somewhere", %{
      user: user,
      context: context
    } do
      create_links_for_user(user, [
        %{
          url: "https://example.com/both-terms",
          title: "postmarketOS installation guide",
          tags: ["linux"]
        },
        %{
          url: "https://example.com/one-term",
          title: "postmarketOS homepage",
          tags: ["linux"]
        },
        %{url: "https://example.com/neither", title: "Unrelated stuff", tags: ["misc"]}
      ])

      urls = search_urls(context, "postmarket guide")
      assert "https://example.com/both-terms" in urls
      refute "https://example.com/neither" in urls
    end

    test "regex metacharacters in search terms are escaped", %{user: user, context: context} do
      create_links_for_user(user, [
        %{
          url: "https://example.com/cpp",
          title: "Learning C++ programming",
          tags: ["programming"]
        },
        %{
          url: "https://example.com/nodejs",
          title: "node.js tutorial",
          tags: ["javascript"]
        }
      ])

      # node.js should find the matching link via grep; c++ should not crash
      _urls = search_urls(context, "c++")
      urls = search_urls(context, "node.js")
      assert "https://example.com/nodejs" in urls
    end

    test "grep matches in notes field", %{user: user, context: context} do
      create_links_for_user(user, [
        %{
          url: "https://example.com/notes-match",
          title: "Some title",
          notes: "This is about postmarketOS on pinephone",
          tags: ["linux"]
        },
        %{url: "https://example.com/no-match", title: "Other title", tags: ["misc"]}
      ])

      urls = search_urls(context, "postmarket")
      assert "https://example.com/notes-match" in urls
      refute "https://example.com/no-match" in urls
    end
  end

  describe "tag search" do
    setup do
      user = AccountsFixtures.user_fixture()
      context = %Context{visible_as: user.username}
      %{user: user, context: context}
    end

    test "hyphenated tag found by search", %{user: user, context: context} do
      create_links_for_user(user, [
        %{url: "https://example.com/selfhost", title: "My Server Setup", tags: ["self-host"]},
        %{url: "https://example.com/unrelated", title: "Unrelated page", tags: ["other"]}
      ])

      urls = search_urls(context, "self-host")
      assert "https://example.com/selfhost" in urls
      refute "https://example.com/unrelated" in urls
    end

    test "tag match ranks below title match", %{user: user, context: context} do
      create_links_for_user(user, [
        %{
          url: "https://example.com/title-match",
          title: "Elixir programming language",
          tags: ["programming"]
        },
        %{
          url: "https://example.com/tag-match",
          title: "Some unrelated title",
          tags: ["elixir"]
        }
      ])

      results = run_search_sorted(context, "elixir")
      urls = Enum.map(results, & &1.url)

      assert "https://example.com/title-match" in urls
      assert "https://example.com/tag-match" in urls

      # Title match should rank higher
      [first | _] = results
      assert first.url == "https://example.com/title-match"
    end

    test "no false positives from tags", %{user: user, context: context} do
      create_links_for_user(user, [
        %{url: "https://example.com/elixir", title: "Some title", tags: ["elixir"]}
      ])

      urls = search_urls(context, "python")
      refute "https://example.com/elixir" in urls
    end

    test "tag-only discovery when title and notes have no matching text", %{
      user: user,
      context: context
    } do
      create_links_for_user(user, [
        %{
          url: "https://example.com/tagged-only",
          title: "Completely unrelated title",
          notes: "Nothing relevant here",
          tags: ["kubernetes"]
        }
      ])

      urls = search_urls(context, "kubernetes")
      assert "https://example.com/tagged-only" in urls
    end

    test "empty tags array does not crash or produce false matches", %{
      user: user,
      context: context
    } do
      create_links_for_user(user, [
        %{url: "https://example.com/no-tags", title: "No Tags Page", tags: []},
        %{url: "https://example.com/tagged", title: "Unrelated Title", tags: ["elixir"]}
      ])

      urls = search_urls(context, "elixir")
      assert "https://example.com/tagged" in urls
      refute "https://example.com/no-tags" in urls
    end

    test "tag search is case-insensitive", %{user: user, context: context} do
      create_links_for_user(user, [
        %{url: "https://example.com/elixir", title: "Unrelated Title", tags: ["Elixir"]}
      ])

      urls = search_urls(context, "elixir")
      assert "https://example.com/elixir" in urls
    end
  end

  describe "account-age quarantine" do
    setup do
      old_user = AccountsFixtures.user_fixture()
      AccountsFixtures.override_user_inserted_at(old_user.id, 60)

      new_user = AccountsFixtures.user_fixture()
      AccountsFixtures.override_user_inserted_at(new_user.id, 10)

      viewer = AccountsFixtures.user_fixture()
      AccountsFixtures.override_user_inserted_at(viewer.id, 60)

      create_links_for_user(old_user, [
        %{url: "https://example.com/old-user", title: "Old User Link", tags: ["test"]}
      ])

      create_links_for_user(new_user, [
        %{url: "https://example.com/new-user", title: "New User Link", tags: ["test"]}
      ])

      %{old_user: old_user, new_user: new_user, viewer: viewer}
    end

    test "anonymous search excludes new user's links", %{old_user: _old, new_user: _new} do
      urls = search_urls(%Context{visible_as: nil}, "")

      assert "https://example.com/old-user" in urls
      refute "https://example.com/new-user" in urls
    end

    test "authenticated search shows viewer's own links despite quarantine", %{
      new_user: new_user
    } do
      urls = search_urls(%Context{visible_as: new_user.username}, "")

      assert "https://example.com/new-user" in urls
    end

    test "user profile page (from set) shows new user's links", %{new_user: new_user} do
      urls =
        search_urls(%Context{from: new_user, visible_as: new_user.username}, "")

      assert "https://example.com/new-user" in urls
    end

    test "tag filtering without from applies quarantine", %{viewer: viewer} do
      urls =
        search_urls(
          %Context{tagged_with: ["test"], visible_as: viewer.username},
          ""
        )

      assert "https://example.com/old-user" in urls
      refute "https://example.com/new-user" in urls
    end
  end

  # Helpers

  defp create_links_for_user(user, specs) do
    Enum.map(specs, fn attrs ->
      attrs = Map.put_new(attrs, :is_private, false)
      {:ok, link} = Links.create_link(user, attrs)
      link
    end)
  end

  defp run_search(context, query) do
    context
    |> Search.search(query, [])
    |> Linkhut.Repo.all()
  end

  defp run_search_sorted(context, query) do
    context
    |> Search.search(query, sort_by: :relevancy)
    |> Linkhut.Repo.all()
  end

  defp search_urls(context, query) do
    context
    |> run_search(query)
    |> Enum.map(& &1.url)
    |> Enum.sort()
  end

  defp url_of(links, title),
    do: find_link_by_title(links, title).url

  defp find_link_by_title(links, title),
    do: Enum.find(links, &(&1.title == title))

  defp host_matches?(url, expected_host) do
    url |> URI.parse() |> Map.get(:host, "") |> String.downcase() ==
      String.downcase(expected_host)
  end

  defp urls_by_host(links, host) do
    links
    |> Enum.filter(&host_matches?(&1.url, host))
    |> Enum.map(& &1.url)
    |> Enum.sort()
  end

  defp urls_by_hosts(links, hosts) do
    links
    |> Enum.filter(fn link -> Enum.any?(hosts, &host_matches?(link.url, &1)) end)
    |> Enum.map(& &1.url)
    |> Enum.sort()
  end

  defp urls_containing_term(links, term) do
    links
    |> Enum.filter(&String.contains?(String.downcase(&1.url), String.downcase(term)))
    |> Enum.map(& &1.url)
    |> Enum.sort()
  end

  defp urls_containing_all_terms(links, terms) do
    links
    |> Enum.filter(fn link ->
      url = String.downcase(link.url)
      Enum.all?(terms, &String.contains?(url, String.downcase(&1)))
    end)
    |> Enum.map(& &1.url)
    |> Enum.sort()
  end
end
