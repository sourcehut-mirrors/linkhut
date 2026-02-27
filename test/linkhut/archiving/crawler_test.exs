defmodule Linkhut.Archiving.CrawlerTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler

  @base_user_agent "LinkhutArchiver/1.0 (web page snapshot for personal archiving)"

  describe "user_agent/0" do
    test "returns base string when suffix is nil" do
      put_suffix(nil)
      assert Crawler.user_agent() == @base_user_agent
    end

    test "returns base string when suffix is empty string" do
      put_suffix("")
      assert Crawler.user_agent() == @base_user_agent
    end

    test "appends suffix when configured" do
      put_suffix("+https://my-instance.com")

      assert Crawler.user_agent() ==
               "LinkhutArchiver/1.0 (web page snapshot for personal archiving; +https://my-instance.com)"
    end
  end

  defp put_suffix(value) do
    original = Application.get_env(:linkhut, Linkhut)
    archiving = Keyword.get(original, :archiving, [])
    updated_archiving = Keyword.put(archiving, :user_agent_suffix, value)
    Application.put_env(:linkhut, Linkhut, Keyword.put(original, :archiving, updated_archiving))

    on_exit(fn ->
      Application.put_env(:linkhut, Linkhut, original)
    end)
  end
end
