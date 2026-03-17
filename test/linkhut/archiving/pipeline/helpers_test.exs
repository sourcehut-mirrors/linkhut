defmodule Linkhut.Archiving.Pipeline.HelpersTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.Pipeline.Helpers

  describe "update_crawl_run_best_effort/2" do
    test "returns updated crawl run on success" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      result = Helpers.update_crawl_run_best_effort(crawl_run, %{error: "test error"})

      assert result.id == crawl_run.id
      assert result.error == "test error"
    end

    test "returns original crawl run on changeset error" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      crawl_run =
        insert(:crawl_run, user_id: user.id, link_id: link.id, url: link.url, state: :processing)

      # state: :bogus should fail validation
      result = Helpers.update_crawl_run_best_effort(crawl_run, %{state: :bogus})

      assert result.id == crawl_run.id
      assert result.state == :processing
    end
  end

  describe "fatal?/1" do
    test "returns true for fatal reasons" do
      assert Helpers.fatal?(:invalid_url)
      assert Helpers.fatal?({:unsupported_scheme, "ftp"})
      assert Helpers.fatal?(:no_eligible_crawlers)
    end

    test "returns false for retryable reasons" do
      refute Helpers.fatal?(:preflight_failed)
      refute Helpers.fatal?({:dns_failed, "example.com"})
      refute Helpers.fatal?({:reserved_address, :loopback})
    end
  end
end
