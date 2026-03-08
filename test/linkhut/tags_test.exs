defmodule Linkhut.TagsTest do
  use Linkhut.DataCase

  alias Linkhut.Links
  alias Linkhut.Tags
  alias Linkhut.AccountsFixtures

  describe "count_tags/1" do
    setup do
      user = AccountsFixtures.user_fixture()
      %{user: user}
    end

    test "returns 0 for user with no links", %{user: user} do
      assert Tags.count_tags(user) == 0
    end

    test "counts distinct tags across links", %{user: user} do
      Links.create_link(user, %{url: "https://a.com", title: "A", tags: ["elixir", "phoenix"]})
      Links.create_link(user, %{url: "https://b.com", title: "B", tags: ["elixir", "otp"]})

      assert Tags.count_tags(user) == 3
    end

    test "deduplicates case-insensitively", %{user: user} do
      Links.create_link(user, %{url: "https://a.com", title: "A", tags: ["Elixir"]})
      Links.create_link(user, %{url: "https://b.com", title: "B", tags: ["elixir"]})

      assert Tags.count_tags(user) == 1
    end

    test "does not count other users' tags", %{user: user} do
      other = AccountsFixtures.user_fixture()
      Links.create_link(other, %{url: "https://other.com", title: "O", tags: ["rust", "wasm"]})
      Links.create_link(user, %{url: "https://mine.com", title: "M", tags: ["elixir"]})

      assert Tags.count_tags(user) == 1
    end
  end
end
