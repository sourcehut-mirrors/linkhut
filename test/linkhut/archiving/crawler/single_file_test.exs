defmodule Linkhut.Archiving.Crawler.SingleFileTest do
  use ExUnit.Case, async: true

  alias Linkhut.Archiving.Crawler.SingleFile
  alias Linkhut.Archiving.PreflightMeta

  describe "accepts/2" do
    test "skips non-webpage or missing content types" do
      for meta <- [
            %PreflightMeta{content_type: "application/pdf", status: 200},
            %PreflightMeta{content_type: "image/png", status: 200},
            %PreflightMeta{content_type: nil, status: 200}
          ] do
        assert SingleFile.accepts("https://example.com", meta) ==
                 {:reject, %{reason: :unsupported_format}},
               "for #{inspect(meta)}"
      end
    end
  end
end

defmodule Linkhut.Archiving.Crawler.SingleFileFetchTest do
  use Linkhut.DataCase

  import ExUnit.CaptureLog
  import Linkhut.Factory

  alias Linkhut.Archiving.Crawler.SingleFile
  alias Linkhut.Archiving.{Log, Snapshot}

  setup do
    dir = Path.join(System.tmp_dir!(), "singlefile_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    bin = Path.join(dir, "single-file")
    File.write!(bin, "#!/bin/sh\necho 'navigation failed'\nexit 3\n")
    File.chmod!(bin, 0o755)

    previous = Application.get_env(:single_file, :path)
    Application.put_env(:single_file, :path, bin)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:single_file, :path, previous),
        else: Application.delete_env(:single_file, :path)

      File.rm_rf(dir)
    end)

    crawl_run = insert(:crawl_run)

    staging_dir = Path.join(dir, "staging")
    File.mkdir_p!(staging_dir)

    %{crawl_run: crawl_run, staging_dir: staging_dir}
  end

  defp events(run), do: Repo.preload(run, :events, force: true).events

  describe "fetch/1 when SingleFile exits with an error" do
    test "records the exit code on the archiving log", %{
      crawl_run: crawl_run,
      staging_dir: staging_dir
    } do
      log = Log.for_snapshot(%Snapshot{id: 7, source: "singlefile"}, crawl_run.id)

      {result, logged} =
        with_log(fn ->
          SingleFile.fetch("https://example.com/page", staging_dir: staging_dir, log: log)
        end)

      assert result == {:error, %{msg: "SingleFile exited with code 3"}}
      assert logged =~ "navigation failed"

      assert %{
               event: "singlefile.exited",
               level: :warning,
               source: "singlefile",
               snapshot_id: 7,
               data: %{"code" => 3}
             } = List.last(events(crawl_run))
    end
  end
end
