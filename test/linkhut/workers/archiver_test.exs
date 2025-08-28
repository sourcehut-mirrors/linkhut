defmodule Linkhut.Workers.ArchiverTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Workers.Archiver

  describe "enqueue/2" do
    test "inserts an Oban job with link data" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link)
      assert job.args[:user_id] || job.args["user_id"] == link.user_id
      assert job.args[:link_id] || job.args["link_id"] == link.id
      assert job.args[:url] || job.args["url"] == link.url
    end

    test "accepts scheduling options" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link, schedule_in: 60)
      assert DateTime.compare(job.scheduled_at, DateTime.utc_now()) == :gt
    end
  end

  describe "perform/1" do
    test "rejects local addresses" do
      job = oban_job(%{"user_id" => 1, "link_id" => 1, "url" => "http://localhost/test"})

      assert {:error, :local_address} = Archiver.perform(job)
    end

    test "rejects URLs without a host" do
      job = oban_job(%{"user_id" => 1, "link_id" => 1, "url" => "not-a-url"})

      assert {:error, :no_host} = Archiver.perform(job)
    end

    test "rejects private IP addresses" do
      for url <- [
            "http://192.168.1.1/page",
            "http://10.0.0.1/page",
            "http://172.16.0.1/page"
          ] do
        job = oban_job(%{"user_id" => 1, "link_id" => 1, "url" => url})
        assert {:error, :local_address} = Archiver.perform(job)
      end
    end

    test "dispatches crawler jobs for valid HTTP URLs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "https://example.com/test")

      job =
        oban_job(%{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => "https://example.com/test"
        })

      assert {:ok, result} = Archiver.perform(job)
      assert %{crawlers: crawlers} = result
      assert length(crawlers) > 0
    end

    test "creates failed snapshot on final attempt with local address" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      # Insert a real Oban job so the FK constraint is satisfied
      {:ok, real_job} = Archiver.enqueue(link)

      job = %Oban.Job{
        id: real_job.id,
        args: %{"user_id" => user.id, "link_id" => link.id, "url" => "http://localhost/test"},
        attempt: 4,
        max_attempts: 4
      }

      assert {:error, :local_address} = Archiver.perform(job)

      snapshot = Repo.get_by(Linkhut.Archiving.Snapshot, link_id: link.id)
      assert snapshot.state == :failed
    end
  end

  defp oban_job(args, opts \\ [])

  defp oban_job(args, opts) do
    %Oban.Job{
      id: opts[:id] || 1,
      args: args,
      attempt: opts[:attempt] || 1,
      max_attempts: opts[:max_attempts] || 4
    }
  end
end
