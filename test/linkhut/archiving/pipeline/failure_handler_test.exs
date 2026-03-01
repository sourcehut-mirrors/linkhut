defmodule Linkhut.Archiving.Pipeline.FailureHandlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.{Archive, Pipeline.FailureHandler}

  describe "finalize_failure/3" do
    test "sets archive to failed on final attempt" do
      {_user, _link, archive} = create_archive()

      assert {:error, :test_reason} =
               FailureHandler.finalize_failure(archive, :test_reason, attempt: 1, max_attempts: 1)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :failed
    end

    test "keeps archive in processing on non-final attempt" do
      {_user, _link, archive} = create_archive()

      assert {:error, :test_reason} =
               FailureHandler.finalize_failure(archive, :test_reason, attempt: 1, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      assert updated.state == :processing
      assert updated.error != nil
    end

    test "records failed step with correct msg" do
      {_user, _link, archive} = create_archive()

      FailureHandler.finalize_failure(archive, :test_reason, attempt: 4, max_attempts: 4)

      updated = Repo.get(Archive, archive.id)
      failed_step = Enum.find(updated.steps, &(&1["step"] == "failed"))
      assert failed_step["detail"]["msg"] == "failed_final"
    end
  end

  describe "record_partial_failure/2" do
    test "records partial_failure step and returns archive" do
      {_user, _link, archive} = create_archive()

      result = FailureHandler.record_partial_failure(archive, :some_reason)

      assert result.id == archive.id
      partial_step = Enum.find(result.steps, &(&1["step"] == "partial_failure"))
      assert partial_step["detail"]["msg"] == "partial_failure"
    end
  end

  describe "safe_after_failure?/2" do
    test "allows third-party after preflight_failed" do
      assert FailureHandler.safe_after_failure?(:preflight_failed, :third_party)
    end

    test "allows third-party after dns_failed" do
      assert FailureHandler.safe_after_failure?({:dns_failed, "example.com"}, :third_party)
    end

    test "rejects target_url after preflight_failed" do
      refute FailureHandler.safe_after_failure?(:preflight_failed, :target_url)
    end

    test "rejects any network access for other reasons" do
      refute FailureHandler.safe_after_failure?(:some_other_reason, :third_party)
      refute FailureHandler.safe_after_failure?(:some_other_reason, :target_url)
    end
  end

  defp create_archive do
    user = insert(:user, credential: build(:credential))
    link = insert(:link, user_id: user.id, url: "https://example.com/page")

    {:ok, archive} =
      Linkhut.Archiving.create_archive(%{
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :processing
      })

    {user, link, archive}
  end
end
