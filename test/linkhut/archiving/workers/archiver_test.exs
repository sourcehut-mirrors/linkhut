defmodule Linkhut.Archiving.Workers.ArchiverTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.CrawlRun
  alias Linkhut.Archiving.Workers.Archiver

  describe "enqueue/2" do
    test "inserts an Oban job with link data" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link)
      args = stringify_keys(job.args)
      assert args["user_id"] == link.user_id
      assert args["link_id"] == link.id
      assert args["url"] == link.url
    end

    test "creates a pending archive alongside the job" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link)

      args = stringify_keys(job.args)
      crawl_run_id = args["crawl_run_id"]
      assert crawl_run_id != nil

      crawl_run = Repo.get(CrawlRun, crawl_run_id)
      assert crawl_run.state == :pending
      assert crawl_run.link_id == link.id
      assert crawl_run.user_id == user.id
      assert crawl_run.url == link.url
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
      args = stringify_keys(job.args)
      assert args["recrawl"] == true
    end

    test "reconciliation enqueue uses reconciliation step" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} =
               Archiver.enqueue(link,
                 only_types: ["singlefile"],
                 reconciliation: true
               )

      args = stringify_keys(job.args)
      crawl_run = Repo.get(CrawlRun, args["crawl_run_id"])

      [created_step | _] = crawl_run.steps
      assert created_step["detail"] == %{
               "msg" => "reconciliation",
               "new_types" => ["singlefile"]
             }
    end

    test "includes only_types in job args when specified" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link, only_types: ["singlefile"])
      args = stringify_keys(job.args)
      assert args["only_types"] == ["singlefile"]
    end

    test "omits only_types from job args when nil" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      assert {:ok, %Oban.Job{} = job} = Archiver.enqueue(link)
      args = stringify_keys(job.args)
      refute Map.has_key?(args, "only_types")
    end
  end

  describe "perform/1" do
    test "marks local addresses as not_archivable" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "http://localhost/test")

      {:ok, job} = Archiver.enqueue(link)

      oban_job = %Oban.Job{
        id: job.id,
        args: stringify_keys(job.args),
        attempt: 1,
        max_attempts: 4
      }

      assert {:ok, %{status: :not_archivable}} = Archiver.perform(oban_job)

      args = stringify_keys(job.args)
      crawl_run = Repo.get(CrawlRun, args["crawl_run_id"])
      assert crawl_run.state == :not_archivable
    end

    test "marks URLs without a host as not_archivable" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "not-a-url")

      {:ok, job} = Archiver.enqueue(link)

      oban_job = %Oban.Job{
        id: job.id,
        args: stringify_keys(job.args),
        attempt: 1,
        max_attempts: 4
      }

      assert {:ok, %{status: :not_archivable}} = Archiver.perform(oban_job)

      args = stringify_keys(job.args)
      crawl_run = Repo.get(CrawlRun, args["crawl_run_id"])
      assert crawl_run.state == :not_archivable
    end

    test "marks private IP addresses as not_archivable" do
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
          args: stringify_keys(job.args),
          attempt: 1,
          max_attempts: 4
        }

        assert {:ok, %{status: :not_archivable}} = Archiver.perform(oban_job)

        args = stringify_keys(job.args)
        crawl_run = Repo.get(CrawlRun, args["crawl_run_id"])
        assert crawl_run.state == :not_archivable
      end
    end

    test "starts processing the pending archive for valid URLs" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id, url: "https://example.com/test")

      {:ok, job} = Archiver.enqueue(link)

      Req.Test.stub(Linkhut.Links.Link, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/html")
        |> Plug.Conn.send_resp(200, "")
      end)

      args = stringify_keys(job.args)

      oban_job = %Oban.Job{
        id: job.id,
        args: args,
        attempt: 1,
        max_attempts: 4
      }

      Archiver.perform(oban_job)

      crawl_run = Repo.get(CrawlRun, args["crawl_run_id"])
      assert crawl_run != nil
      assert crawl_run.link_id == link.id

      # Archive is processing (no longer pending) — pipeline may set it to :processing or :failed
      # depending on crawler outcomes, but it should not remain :pending
      assert crawl_run.state != :pending
    end

    test "returns :ok when archive not found" do
      oban_job = %Oban.Job{
        id: 1,
        args: %{
          "crawl_run_id" => 999_999,
          "user_id" => 1,
          "link_id" => 1,
          "url" => "https://example.com"
        },
        attempt: 1,
        max_attempts: 4
      }

      assert :ok = Archiver.perform(oban_job)
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
