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

  describe "not_archivable?/1" do
    test "returns true for invalid_url" do
      assert Helpers.not_archivable?(:invalid_url)
    end

    test "returns true for unsupported_scheme" do
      assert Helpers.not_archivable?({:unsupported_scheme, "ftp"})
    end

    test "returns true for no_eligible_crawlers" do
      assert Helpers.not_archivable?(:no_eligible_crawlers)
    end

    test "returns true for reserved_address" do
      assert Helpers.not_archivable?({:reserved_address, :loopback})
    end

    test "returns true for file_too_large" do
      assert Helpers.not_archivable?({:file_too_large, 100_000_000})
    end

    test "returns false for other reasons" do
      refute Helpers.not_archivable?(:preflight_failed)
      refute Helpers.not_archivable?({:dns_failed, "example.com"})
      refute Helpers.not_archivable?({:http_error, 404})
    end
  end

  describe "fatal?/1" do
    test "returns true for 4xx http errors" do
      assert Helpers.fatal?({:http_error, 400})
      assert Helpers.fatal?({:http_error, 403})
      assert Helpers.fatal?({:http_error, 404})
      assert Helpers.fatal?({:http_error, 410})
    end

    test "returns false for 429 (rate limited)" do
      refute Helpers.fatal?({:http_error, 429})
    end

    test "returns false for 5xx http errors" do
      refute Helpers.fatal?({:http_error, 500})
      refute Helpers.fatal?({:http_error, 503})
    end

    test "returns false for retryable reasons" do
      refute Helpers.fatal?(:preflight_failed)
      refute Helpers.fatal?({:dns_failed, "example.com"})
    end
  end
end
