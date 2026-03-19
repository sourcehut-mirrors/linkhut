defmodule Linkhut.Archiving.Workers.ReconcilerTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.Archiving.Workers.{Archiver, Reconciler}

  defmodule FakeCrawlerA do
    def source_type, do: "singlefile"
    def module_version, do: "1"
    def meta, do: %{tool_name: "SingleFile", tool_version: "1.0", version: module_version()}
    def network_access, do: :target_url
    def queue, do: :crawler
    def can_handle?(_, _), do: true
    def fetch(_), do: {:error, %{msg: "stub"}}
  end

  defmodule FakeCrawlerB do
    def source_type, do: "httpfetch"
    def module_version, do: "1"
    def meta, do: %{tool_name: "HttpFetch", tool_version: nil, version: module_version()}
    def network_access, do: :target_url
    def queue, do: :crawler
    def can_handle?(_, _), do: true
    def fetch(_), do: {:error, %{msg: "stub"}}
  end

  setup do
    put_override(Linkhut.Archiving, :crawlers, [FakeCrawlerA, FakeCrawlerB])
    put_override(Linkhut.Archiving, :mode, :enabled)
    :ok
  end

  test "does nothing when archiving is disabled" do
    put_override(Linkhut.Archiving, :mode, :disabled)

    assert :ok = Reconciler.perform(%Oban.Job{})
    assert all_enqueued(worker: Archiver) == []
  end

  test "does nothing when all sources are covered" do
    user = insert(:user, credential: build(:credential), type: :active)
    link = insert(:link, user_id: user.id)

    cr =
      insert(:crawl_run,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :complete
      )

    # Cover both sources with snapshots at current module_version
    insert(:snapshot,
      user_id: user.id,
      link_id: link.id,
      crawl_run_id: cr.id,
      format: "webpage",
      source: "singlefile",
      state: :complete,
      crawler_meta: %{"version" => "1"}
    )

    insert(:snapshot,
      user_id: user.id,
      link_id: link.id,
      crawl_run_id: cr.id,
      format: "webpage",
      source: "httpfetch",
      state: :complete,
      crawler_meta: %{"version" => "1"}
    )

    assert :ok = Reconciler.perform(%Oban.Job{})
    assert all_enqueued(worker: Archiver) == []
  end

  test "enqueues reconciliation job for link with missing source" do
    user = insert(:user, credential: build(:credential), type: :active)
    link = insert(:link, user_id: user.id)

    cr =
      insert(:crawl_run,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :complete
      )

    # Only "singlefile" covered — "httpfetch" is missing
    insert(:snapshot,
      user_id: user.id,
      link_id: link.id,
      crawl_run_id: cr.id,
      format: "webpage",
      source: "singlefile",
      state: :complete,
      crawler_meta: %{"version" => "1"}
    )

    assert :ok = Reconciler.perform(%Oban.Job{})

    jobs = all_enqueued(worker: Archiver)
    assert length(jobs) == 1
    [job] = jobs
    assert job.args["only_types"] == ["httpfetch"]
  end

  test "skips links with in-flight crawl runs" do
    user = insert(:user, credential: build(:credential), type: :active)
    link = insert(:link, user_id: user.id)

    insert(:crawl_run,
      user_id: user.id,
      link_id: link.id,
      url: link.url,
      state: :complete
    )

    # In-flight
    insert(:crawl_run,
      user_id: user.id,
      link_id: link.id,
      url: link.url,
      state: :processing
    )

    assert :ok = Reconciler.perform(%Oban.Job{})
    assert all_enqueued(worker: Archiver) == []
  end

  test "skips sources already covered by existing snapshot" do
    user = insert(:user, credential: build(:credential), type: :active)
    link = insert(:link, user_id: user.id)

    cr =
      insert(:crawl_run,
        user_id: user.id,
        link_id: link.id,
        url: link.url,
        state: :complete
      )

    # "singlefile" covered
    insert(:snapshot,
      user_id: user.id,
      link_id: link.id,
      crawl_run_id: cr.id,
      format: "webpage",
      source: "singlefile",
      state: :complete,
      crawler_meta: %{"version" => "1"}
    )

    assert :ok = Reconciler.perform(%Oban.Job{})

    jobs = all_enqueued(worker: Archiver)
    assert length(jobs) == 1
    [job] = jobs
    assert job.args["only_types"] == ["httpfetch"]
  end
end
