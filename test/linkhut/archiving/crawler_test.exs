defmodule Linkhut.Archiving.CrawlerTest do
  use ExUnit.Case, async: true

  import Linkhut.Config, only: [put_override: 3]

  alias Linkhut.Archiving.Crawler

  @base_user_agent "LinkhutArchiver/1.0 (web page snapshot for personal archiving)"

  describe "user_agent/0" do
    test "returns base string when suffix is nil" do
      put_override(Linkhut.Archiving, :user_agent_suffix, nil)
      assert Crawler.user_agent() == @base_user_agent
    end

    test "returns base string when suffix is empty string" do
      put_override(Linkhut.Archiving, :user_agent_suffix, "")
      assert Crawler.user_agent() == @base_user_agent
    end

    test "appends suffix when configured" do
      put_override(Linkhut.Archiving, :user_agent_suffix, "+https://my-instance.com")

      assert Crawler.user_agent() ==
               "LinkhutArchiver/1.0 (web page snapshot for personal archiving; +https://my-instance.com)"
    end
  end
end
