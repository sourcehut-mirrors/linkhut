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
        # owner context ensures site filter logic doesn’t get confounded by visibility rules
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
      expected_url = links |> find_link_by_title("Example Page 1") |> Map.fetch!(:url)
      assert [%{url: ^expected_url}] = results
    end

    test "returns empty results for non-matching site", %{context: context} do
      assert [] == run_search(context, "site:nonexistent.com")
    end

    test "works with only site filters (no text search)", %{context: context, links: links} do
      results = run_search(context, "site:github.com")
      expected_url = links |> find_link_by_host("github.com") |> Map.fetch!(:url)
      assert [%{url: ^expected_url}] = results
    end

    test "case insensitive site filtering", %{context: context, links: links} do
      assert search_urls(context, "site:EXAMPLE.COM") == urls_by_host(links, "example.com")
    end
  end

  describe "basic search functionality" do
    setup do
      owner = AccountsFixtures.user_fixture()
      other = AccountsFixtures.user_fixture()

      owner_links =
        create_links_for_user(owner, [
          %{
            url: "https://example.com/elixir",
            title: "Elixir Programming",
            tags: ["elixir", "programming"],
            is_private: false
          },
          %{
            url: "https://example.com/phoenix",
            title: "Phoenix Framework",
            tags: ["phoenix", "elixir"],
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

      other_links =
        create_links_for_user(other, [
          %{
            url: "https://other.com/public",
            title: "Other User Public",
            tags: ["public"],
            is_private: false
          },
          %{
            url: "https://other.com/private",
            title: "Other User Private",
            tags: ["private"],
            is_private: true
          }
        ])

      %{
        owner: owner,
        other: other,
        owner_links: owner_links,
        other_links: other_links
      }
    end

    test "public visitor does not see private, unread, or via:ifttt links", %{
      owner: owner,
      owner_links: owner_links
    } do
      ctx = %Context{from: owner, visible_as: nil}
      urls = run_search(ctx, "") |> Enum.map(& &1.url)

      refute includes_url?(urls, url_of(owner_links, "Private Link"))
      refute includes_url?(urls, url_of(owner_links, "Unread Link"))
      refute includes_url?(urls, url_of(owner_links, "IFTTT Link"))

      assert includes_url?(urls, url_of(owner_links, "Elixir Programming"))
      assert includes_url?(urls, url_of(owner_links, "Phoenix Framework"))
    end

    test "owner sees their private, unread and via:ifttt links", %{
      owner: owner,
      owner_links: owner_links
    } do
      ctx = %Context{from: owner, visible_as: owner.username}
      urls = run_search(ctx, "") |> Enum.map(& &1.url)

      assert includes_url?(urls, url_of(owner_links, "Private Link"))
      assert includes_url?(urls, url_of(owner_links, "Unread Link"))
      assert includes_url?(urls, url_of(owner_links, "IFTTT Link"))
    end

    test "text search ranks and filters by query", %{
      owner: owner,
      owner_links: owner_links
    } do
      ctx = %Context{from: owner, visible_as: owner.username}
      urls = run_search(ctx, "Elixir") |> Enum.map(& &1.url)

      assert includes_url?(urls, url_of(owner_links, "Elixir Programming"))
      assert includes_url?(urls, url_of(owner_links, "Phoenix Framework"))
    end

    test "filters by tag", %{owner: owner, owner_links: owner_links} do
      # tag filtering is applied via Context.tagged_with
      ctx = %Context{from: owner, visible_as: nil, tagged_with: ["elixir"]}

      urls =
        run_search(ctx, "")
        |> Enum.map(& &1.url)
        |> Enum.sort()

      assert urls ==
               Enum.sort([
                 url_of(owner_links, "Elixir Programming"),
                 url_of(owner_links, "Phoenix Framework")
               ])
    end

    test "site filter combines with visibility rules for public visitor", %{
      owner: owner,
      owner_links: owner_links
    } do
      ctx = %Context{from: owner, visible_as: nil}
      urls = run_search(ctx, "site:example.com") |> Enum.map(& &1.url)

      # Should exclude private/unread/ifttt for public visitor
      refute includes_url?(urls, url_of(owner_links, "Private Link"))
      refute includes_url?(urls, url_of(owner_links, "Unread Link"))
      refute includes_url?(urls, url_of(owner_links, "IFTTT Link"))

      assert includes_url?(urls, url_of(owner_links, "Elixir Programming"))
      assert includes_url?(urls, url_of(owner_links, "Phoenix Framework"))
    end

    test "cross-user visibility: public visitor can see other user's public link only", %{
      other: other,
      other_links: other_links
    } do
      ctx = %Context{from: other, visible_as: nil}
      urls = run_search(ctx, "") |> Enum.map(& &1.url)

      assert includes_url?(urls, url_of(other_links, "Other User Public"))
      refute includes_url?(urls, url_of(other_links, "Other User Private"))
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

  defp host_matches?(url, expected_host) do
    url
    |> URI.parse()
    |> Map.get(:host)
    |> to_string()
    |> String.downcase()
    |> Kernel.==(String.downcase(expected_host))
  end

  defp find_link_by_title(links, title),
    do: Enum.find(links, &(&1.title == title))

  defp find_link_by_host(links, host),
    do: Enum.find(links, &host_matches?(&1.url, host))

  defp url_of(links, title),
    do: links |> find_link_by_title(title) |> Map.fetch!(:url)

  defp includes_url?(urls, url), do: Enum.any?(urls, &(&1 == url))
end
