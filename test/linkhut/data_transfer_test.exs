defmodule Linkhut.DataTransferTest do
  use Linkhut.DataCase

  import Linkhut.Factory

  alias Linkhut.DataTransfer
  alias Linkhut.DataTransfer.Workers.Importer

  @valid_bookmark_html """
  <!DOCTYPE NETSCAPE-Bookmark-file-1>
  <DL><p>
  <DT><A HREF="https://example.com/import-test" ADD_DATE="1678900000" TAGS="test">Import Test</A>
  <DD>A test bookmark
  </DL>
  """

  @invalid_bookmark_html """
  <!DOCTYPE NETSCAPE-Bookmark-file-1>
  <DL><p>
  <DT><A>invalid bookmark</A>
  </DL>
  """

  @multiple_bookmarks_html """
  <!DOCTYPE NETSCAPE-Bookmark-file-1>
  <DL><p>
  <DT><A HREF="https://one.example.com" TAGS="test">One</A>
  <DT><A HREF="https://two.example.com" TAGS="test">Two</A>
  <DT><A HREF="https://three.example.com" TAGS="test">Three</A>
  </DL>
  """

  @unsupported_content "just some plain text, not a bookmark file"

  setup do
    user = insert(:user)
    %{user: user}
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "import_test_#{System.unique_integer([:positive])}.html")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  # Enqueue via Oban to get a real job ID, then call perform directly
  # with a matching Oban.Job struct so the import record can be found.
  defp enqueue_and_perform(user, file, overrides \\ %{}) do
    {:ok, import} = DataTransfer.create_import(user, file, overrides)
    job_id = import.job_id

    # Build an Oban.Job struct matching what the real queue would provide
    oban_job = %Oban.Job{
      id: job_id,
      args: %{"user_id" => user.id, "file" => file, "overrides" => overrides}
    }

    result = Importer.perform(oban_job)
    {result, job_id}
  end

  describe "create_import/3" do
    test "imports a valid bookmark file", %{user: user} do
      path = write_temp_file(@valid_bookmark_html)
      {result, job_id} = enqueue_and_perform(user, path)

      assert :ok = result

      import = DataTransfer.get_import(user.id, job_id)
      assert import.state == :complete
      assert import.total == 1
      assert import.saved == 1
      assert import.failed == 0
      assert import.invalid == 0
    end

    test "imports a file with an invalid bookmark", %{user: user} do
      path = write_temp_file(@invalid_bookmark_html)
      {result, job_id} = enqueue_and_perform(user, path)

      assert :ok = result

      import = DataTransfer.get_import(user.id, job_id)
      assert import.state == :complete
      assert import.total == 1
      assert import.saved == 0
      assert import.failed == 0
      assert import.invalid == 1
      assert import.invalid_entries == ["No URL found for entry with title: 'invalid bookmark'"]
    end

    test "handles multiple bookmarks", %{user: user} do
      path = write_temp_file(@multiple_bookmarks_html)
      {result, job_id} = enqueue_and_perform(user, path)

      assert :ok = result

      import = DataTransfer.get_import(user.id, job_id)
      assert import.state == :complete
      assert import.total == 3
      assert import.saved == 3
    end

    test "marks import as failed for unsupported format", %{user: user} do
      path = write_temp_file(@unsupported_content)
      {result, job_id} = enqueue_and_perform(user, path)

      assert {:cancel, :unsupported_format} = result

      import = DataTransfer.get_import(user.id, job_id)
      assert import.state == :failed
      assert import.invalid_entries == ["Unsupported file format"]
    end

    test "applies is_private override", %{user: user} do
      path = write_temp_file(@valid_bookmark_html)
      {result, job_id} = enqueue_and_perform(user, path, %{"is_private" => "true"})

      assert :ok = result

      import = DataTransfer.get_import(user.id, job_id)
      assert import.state == :complete
      assert import.saved == 1

      link = Linkhut.Links.get("https://example.com/import-test", user.id)
      assert link.is_private == true
    end

    test "cleans up the uploaded file", %{user: user} do
      path = write_temp_file(@valid_bookmark_html)
      {_result, _job_id} = enqueue_and_perform(user, path)

      refute File.exists?(path)
    end

    test "tracks duplicate URL as failed record", %{user: user} do
      # First import succeeds
      path1 = write_temp_file(@valid_bookmark_html)
      {_result, _job_id} = enqueue_and_perform(user, path1)

      # Second import of same bookmark — duplicate URL should fail
      path2 = write_temp_file(@valid_bookmark_html)
      {_result, job_id2} = enqueue_and_perform(user, path2)

      import2 = DataTransfer.get_import(user.id, job_id2)
      assert import2.state == :complete
      assert import2.total == 1
      assert import2.saved == 0
      assert import2.failed == 1
    end
  end

  describe "has_active_import?/1" do
    test "returns false when user has no imports", %{user: user} do
      refute DataTransfer.has_active_import?(user.id)
    end

    test "returns false after import completes", %{user: user} do
      path = write_temp_file(@valid_bookmark_html)
      {_result, _job_id} = enqueue_and_perform(user, path)

      refute DataTransfer.has_active_import?(user.id)
    end

    test "returns true when import is queued", %{user: user} do
      path = write_temp_file(@valid_bookmark_html)
      {:ok, _import} = DataTransfer.create_import(user, path, %{})

      assert DataTransfer.has_active_import?(user.id)
    end
  end
end
