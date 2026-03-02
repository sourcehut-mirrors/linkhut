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
      assert [%{url: ^expected_url}] = results
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
