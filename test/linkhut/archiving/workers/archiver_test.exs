defmodule Linkhut.Archiving.Workers.ArchiverTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.Workers.Archiver
  alias Linkhut.Archiving.Archive

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

    test "includes recrawl flag when specified" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link, recrawl: true)
      assert job.args[:recrawl] || job.args["recrawl"] == true
    end
  end

  describe "perform/1" do
    test "rejects local addresses" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/test")

      {:ok, job} = Archiver.enqueue(link)

      oban_job = %Oban.Job{
        id: job.id,
        args: %{"user_id" => user.id, "link_id" => link.id, "url" => "http://localhost/test"},
        attempt: 1,
        max_attempts: 4
      }

      assert {:error, {:reserved_address, {:reserved, :loopback, "localhost"}}} =
               Archiver.perform(oban_job)
    end

    test "rejects URLs without a host" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "not-a-url")

      {:ok, job} = Archiver.enqueue(link)

      oban_job = %Oban.Job{
        id: job.id,
        args: %{"user_id" => user.id, "link_id" => link.id, "url" => "not-a-url"},
        attempt: 1,
        max_attempts: 4
      }

      assert {:error, _} = Archiver.perform(oban_job)
    end

    test "rejects private IP addresses" do
      user = insert(:user, credential: build(:credential))

      for url <- [
            "http://192.168.1.1/page",
            "http://10.0.0.1/page",
            "http://172.16.0.1/page"
          ] do
        link = insert(:link, user_id: user.id, url: url)
        {:ok, job} = Archiver.enqueue(link)

        oban_job = %Oban.Job{
          id: job.id,
          args: %{"user_id" => user.id, "link_id" => link.id, "url" => url},
          attempt: 1,
          max_attempts: 4
        }

        assert {:error, {:reserved_address, _}} = Archiver.perform(oban_job)
      end
    end

    test "creates an archive record for valid URLs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "https://example.com/test")

      {:ok, job} = Archiver.enqueue(link)

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        Plug.Conn.send_resp(conn, 200, "")
      end)

      oban_job = %Oban.Job{
        id: job.id,
        args: %{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => "https://example.com/test"
        },
        attempt: 1,
        max_attempts: 4
      }

      Archiver.perform(oban_job)

      archive = Repo.get_by(Archive, job_id: job.id)
      assert archive != nil
      assert archive.link_id == link.id
    end
  end
end
