defmodule Linkhut.Archiving.Pipeline.FailureHandlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.{CrawlRun, Pipeline.FailureHandler}

  describe "finalize_failure/3" do
    test "sets archive to failed on final attempt" do
      {_user, _link, crawl_run} = create_crawl_run()

      assert {:error, :test_reason} =
               FailureHandler.finalize_failure(crawl_run, :test_reason,
                 attempt: 1,
                 max_attempts: 1
               )

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :failed
    end

    test "keeps archive in processing on non-final attempt" do
      {_user, _link, crawl_run} = create_crawl_run()

      assert {:error, :test_reason} =
               FailureHandler.finalize_failure(crawl_run, :test_reason,
                 attempt: 1,
                 max_attempts: 4
               )

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :processing
      assert updated.error != nil
    end

    test "records failed step with correct msg" do
      {_user, _link, crawl_run} = create_crawl_run()

      FailureHandler.finalize_failure(crawl_run, :test_reason, attempt: 4, max_attempts: 4)

      updated = Repo.get(CrawlRun, crawl_run.id)
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
    end
  end

  describe "finalize_not_archivable/3" do
    test "sets state to :not_archivable" do
      {_user, _link, crawl_run} = create_crawl_run()

      assert {:ok, %{status: :not_archivable}} =
               FailureHandler.finalize_not_archivable(crawl_run, :invalid_url, [])

      updated = Repo.get(CrawlRun, crawl_run.id)
      assert updated.state == :not_archivable
    end

    test "records not_archivable step with reason" do
      {_user, _link, crawl_run} = create_crawl_run()

      assert {:ok, %{crawl_run: result_crawl_run}} =
               FailureHandler.finalize_not_archivable(
                 crawl_run,
                 {:unsupported_scheme, "ftp"},
                 []
               )

      updated = Repo.get(CrawlRun, crawl_run.id)
      step = Enum.find(updated.steps, &(&1["step"] == "not_archivable"))
      assert step["detail"]["msg"] == "not_archivable"
      assert step["detail"]["reason"] == "unsupported_scheme:ftp"
      assert result_crawl_run.id == crawl_run.id
    end

    test "returns {:ok, %{status: :not_archivable}}" do
      {_user, _link, crawl_run} = create_crawl_run()

      result =
        FailureHandler.finalize_not_archivable(crawl_run, :no_eligible_crawlers, [])

      assert {:ok, %{crawl_run: _, status: :not_archivable}} = result
    end

    test "records error string for each reason type" do
      {_user, _link, crawl_run1} = create_crawl_run()
      {_user, _link, crawl_run2} = create_crawl_run()
      {_user, _link, crawl_run3} = create_crawl_run()
      {_user, _link, crawl_run4} = create_crawl_run()

      FailureHandler.finalize_not_archivable(crawl_run1, :invalid_url, [])
      FailureHandler.finalize_not_archivable(crawl_run2, {:unsupported_scheme, "ftp"}, [])
      FailureHandler.finalize_not_archivable(crawl_run3, :no_eligible_crawlers, [])
      FailureHandler.finalize_not_archivable(crawl_run4, {:file_too_large, 999}, [])

      assert Repo.get(CrawlRun, crawl_run1.id).error == "invalid_url"
      assert Repo.get(CrawlRun, crawl_run2.id).error == "unsupported_scheme:ftp"
      assert Repo.get(CrawlRun, crawl_run3.id).error == "no_eligible_crawlers"
      assert Repo.get(CrawlRun, crawl_run4.id).error == "file_too_large"
    end
  end

  defp create_crawl_run do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, crawl_run} =
      Linkhut.Archiving.create_crawl_run(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, crawl_run}
  end
end
