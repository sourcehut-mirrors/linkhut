defmodule Linkhut.Workers.CrawlerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Workers.Crawler
  alias Linkhut.Archiving.Snapshot

  describe "perform/1" do
    test "creates failed snapshot for unsupported crawler type" do
      user = insert(:user, credential: build(:credential))
      link = insert(:link, user_id: user.id)

      # Insert a real Oban job so the FK constraint is satisfied
      {:ok, real_job} =
        Crawler.new(%{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => "https://example.com",
          "type" => "unsupported"
        })
        |> Oban.insert()

      job = %Oban.Job{
        id: real_job.id,
        args: %{
          "user_id" => user.id,
          "link_id" => link.id,
          "url" => "https://example.com",
          "type" => "unsupported"
        },
        attempt: 1,
        max_attempts: 4
      }

      Crawler.perform(job)

      snapshot = Repo.get_by(Snapshot, link_id: link.id)
      assert snapshot.state == :failed
    end
  end
end
