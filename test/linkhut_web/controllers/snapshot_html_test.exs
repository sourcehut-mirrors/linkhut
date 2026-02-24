defmodule LinkhutWeb.SnapshotHTMLTest do
  use ExUnit.Case, async: true

  alias LinkhutWeb.SnapshotHTML

  describe "format_file_size/1" do
    test "returns 'Unknown' for nil" do
      assert SnapshotHTML.format_file_size(nil) == "Unknown"
    end

    test "formats bytes" do
      assert SnapshotHTML.format_file_size(500) == "500 bytes"
    end

    test "formats kilobytes" do
      assert SnapshotHTML.format_file_size(2048) == "2.0 KB"
    end

    test "formats megabytes" do
      assert SnapshotHTML.format_file_size(5_242_880) == "5.0 MB"
    end

    test "formats gigabytes" do
      assert SnapshotHTML.format_file_size(2_147_483_648) == "2.0 GB"
    end
  end

  describe "format_datetime/1" do
    test "formats a DateTime to date string" do
      dt = ~U[2025-03-15 10:30:00Z]
      assert SnapshotHTML.format_datetime(dt) == "2025-03-15"
    end

    test "returns 'Unknown' for nil" do
      assert SnapshotHTML.format_datetime(nil) == "Unknown"
    end

    test "returns 'Unknown' for non-DateTime" do
      assert SnapshotHTML.format_datetime("not a date") == "Unknown"
    end
  end

  describe "format_processing_time/1" do
    test "returns 'Unknown' for nil" do
      assert SnapshotHTML.format_processing_time(nil) == "Unknown"
    end

    test "formats milliseconds" do
      assert SnapshotHTML.format_processing_time(500) == "500 ms"
    end

    test "formats seconds" do
      assert SnapshotHTML.format_processing_time(3500) == "3.5 sec"
    end

    test "formats minutes" do
      assert SnapshotHTML.format_processing_time(120_000) == "2.0 min"
    end
  end

  describe "crawler_display_name/1" do
    test "returns 'SingleFile' for singlefile" do
      assert SnapshotHTML.crawler_display_name("singlefile") == "SingleFile"
    end

    test "returns 'Wget' for wget" do
      assert SnapshotHTML.crawler_display_name("wget") == "Wget"
    end

    test "capitalizes unknown types" do
      assert SnapshotHTML.crawler_display_name("custom") == "Custom"
    end
  end

  describe "format_relative_datetime/1" do
    test "formats a DateTime as relative" do
      dt = DateTime.utc_now()
      assert SnapshotHTML.format_relative_datetime(dt) =~ "now"
    end

    test "returns 'Unknown' for nil" do
      assert SnapshotHTML.format_relative_datetime(nil) == "Unknown"
    end
  end

  describe "format_response_code/1" do
    test "returns 'Unknown' for nil" do
      assert SnapshotHTML.format_response_code(nil) == "Unknown"
    end

    test "formats common codes with labels" do
      assert SnapshotHTML.format_response_code(200) == "200 OK"
      assert SnapshotHTML.format_response_code(301) == "301 Moved"
      assert SnapshotHTML.format_response_code(302) == "302 Found"
      assert SnapshotHTML.format_response_code(403) == "403 Forbidden"
      assert SnapshotHTML.format_response_code(404) == "404 Not Found"
      assert SnapshotHTML.format_response_code(500) == "500 Server Error"
    end

    test "formats unknown codes as raw integer" do
      assert SnapshotHTML.format_response_code(418) == "418"
    end
  end

  describe "state_label/1" do
    test "returns labels for known states" do
      assert SnapshotHTML.state_label(:pending) == "Pending"
      assert SnapshotHTML.state_label(:crawling) == "Crawling"
      assert SnapshotHTML.state_label(:complete) == "Complete"
      assert SnapshotHTML.state_label(:failed) == "Failed"
      assert SnapshotHTML.state_label(:pending_deletion) == "Pending deletion"
    end

    test "returns 'Unknown' for unrecognized state" do
      assert SnapshotHTML.state_label(:other) == "Unknown"
    end
  end

  describe "state_class/1" do
    test "returns CSS classes for known states" do
      assert SnapshotHTML.state_class(:pending) == "pending"
      assert SnapshotHTML.state_class(:crawling) == "crawling"
      assert SnapshotHTML.state_class(:complete) == "complete"
      assert SnapshotHTML.state_class(:failed) == "failed"
      assert SnapshotHTML.state_class(:pending_deletion) == "pending-deletion"
    end

    test "returns empty string for unrecognized state" do
      assert SnapshotHTML.state_class(:other) == ""
    end
  end

  describe "final_url/1" do
    test "extracts final_url from string-keyed metadata" do
      assert SnapshotHTML.final_url(%{archive_metadata: %{"final_url" => "https://example.com"}}) ==
               "https://example.com"
    end

    test "returns nil for missing metadata" do
      assert SnapshotHTML.final_url(%{archive_metadata: nil}) == nil
    end

    test "returns nil for missing final_url key" do
      assert SnapshotHTML.final_url(%{archive_metadata: %{}}) == nil
    end
  end

  describe "crawler_version/1" do
    test "extracts from string-keyed metadata" do
      assert SnapshotHTML.crawler_version(%{archive_metadata: %{"crawler_version" => "1.0"}}) ==
               "1.0"
    end

    test "returns nil when not available" do
      assert SnapshotHTML.crawler_version(%{archive_metadata: nil}) == nil
    end
  end

  describe "crawler_label/1" do
    test "returns display name when no version" do
      assert SnapshotHTML.crawler_label(%{type: "singlefile", archive_metadata: nil}) ==
               "SingleFile"
    end

    test "returns display name with version" do
      assert SnapshotHTML.crawler_label(%{
               type: "singlefile",
               archive_metadata: %{"crawler_version" => "1.2.3"}
             }) == "SingleFile 1.2.3"
    end

    test "handles nil archive_metadata" do
      assert SnapshotHTML.crawler_label(%{type: "singlefile", archive_metadata: nil}) ==
               "SingleFile"
    end

    test "handles missing type" do
      assert SnapshotHTML.crawler_label(%{archive_metadata: nil}) == "Unknown"
    end
  end

  describe "archive_state_label/1" do
    test "returns labels for known archive states" do
      assert SnapshotHTML.archive_state_label(:active) == "Active"
      assert SnapshotHTML.archive_state_label(:failed) == "Failed"
      assert SnapshotHTML.archive_state_label(:pending_deletion) == "Pending deletion"
    end

    test "returns 'Unknown' for unrecognized state" do
      assert SnapshotHTML.archive_state_label(:other) == "Unknown"
    end
  end

  describe "archive_state_class/1" do
    test "returns CSS classes for known archive states" do
      assert SnapshotHTML.archive_state_class(:active) == "active"
      assert SnapshotHTML.archive_state_class(:failed) == "failed"
      assert SnapshotHTML.archive_state_class(:pending_deletion) == "pending-deletion"
    end

    test "returns empty string for unrecognized state" do
      assert SnapshotHTML.archive_state_class(:other) == ""
    end
  end

  describe "format_step_time/1" do
    test "formats ISO 8601 timestamp to HH:MM:SS" do
      assert SnapshotHTML.format_step_time("2026-02-26T14:30:45Z") == "14:30:45"
    end

    test "returns empty string for nil" do
      assert SnapshotHTML.format_step_time(nil) == ""
    end

    test "returns raw string for invalid timestamp" do
      assert SnapshotHTML.format_step_time("not-a-date") == "not-a-date"
    end

    test "returns empty string for non-binary" do
      assert SnapshotHTML.format_step_time(123) == ""
    end
  end

  describe "original_url/1" do
    test "extracts original_url from string-keyed metadata" do
      assert SnapshotHTML.original_url(%{
               archive_metadata: %{"original_url" => "https://original.com"}
             }) ==
               "https://original.com"
    end

    test "returns nil for missing metadata" do
      assert SnapshotHTML.original_url(%{archive_metadata: nil}) == nil
    end

    test "returns nil for missing original_url key" do
      assert SnapshotHTML.original_url(%{archive_metadata: %{}}) == nil
    end
  end

  describe "crawl_steps/1" do
    test "extracts steps from string-keyed crawl_info" do
      steps = [%{"step" => "fetch", "at" => "2026-02-26T14:30:45Z"}]
      assert SnapshotHTML.crawl_steps(%{crawl_info: %{"steps" => steps}}) == steps
    end

    test "returns empty list for nil crawl_info" do
      assert SnapshotHTML.crawl_steps(%{crawl_info: nil}) == []
    end

    test "returns empty list for missing steps key" do
      assert SnapshotHTML.crawl_steps(%{crawl_info: %{}}) == []
    end

    test "returns empty list for missing crawl_info field" do
      assert SnapshotHTML.crawl_steps(%{}) == []
    end
  end

  describe "visible_snapshots/2" do
    test "returns all snapshots when show_all is true" do
      snapshots = [
        %{state: :complete},
        %{state: :failed},
        %{state: :pending}
      ]

      assert SnapshotHTML.visible_snapshots(snapshots, true) == snapshots
    end

    test "returns only complete snapshots when show_all is false" do
      snapshots = [
        %{state: :complete},
        %{state: :failed},
        %{state: :pending}
      ]

      assert SnapshotHTML.visible_snapshots(snapshots, false) == [%{state: :complete}]
    end
  end

  describe "step_class/1" do
    test "returns step-failed for failed step" do
      assert SnapshotHTML.step_class(%{"step" => "failed"}) == "step-failed"
    end

    test "returns step-complete for complete step" do
      assert SnapshotHTML.step_class(%{"step" => "complete"}) == "step-complete"
    end

    test "returns empty string for other steps" do
      assert SnapshotHTML.step_class(%{"step" => "created"}) == ""
    end
  end

  describe "step_display_name/1" do
    test "capitalizes step name" do
      assert SnapshotHTML.step_display_name(%{"step" => "created"}) == "Created"
      assert SnapshotHTML.step_display_name(%{"step" => "head_preflight"}) == "Head_preflight"
    end

    test "returns Unknown for missing step" do
      assert SnapshotHTML.step_display_name(%{}) == "Unknown"
    end
  end

  describe "content_type/1" do
    test "extracts content_type from string-keyed metadata" do
      assert SnapshotHTML.content_type(%{archive_metadata: %{"content_type" => "text/html"}}) ==
               "text/html"
    end

    test "returns nil for missing metadata" do
      assert SnapshotHTML.content_type(%{archive_metadata: nil}) == nil
    end

    test "returns nil for missing content_type key" do
      assert SnapshotHTML.content_type(%{archive_metadata: %{}}) == nil
    end
  end

  describe "max_retry_count/1" do
    test "returns 0 for empty list" do
      assert SnapshotHTML.max_retry_count([]) == 0
    end

    test "returns max retry_count across snapshots" do
      snapshots = [
        %{retry_count: 1},
        %{retry_count: 3},
        %{retry_count: 2}
      ]

      assert SnapshotHTML.max_retry_count(snapshots) == 3
    end

    test "treats nil retry_count as 0" do
      snapshots = [
        %{retry_count: nil},
        %{retry_count: 2}
      ]

      assert SnapshotHTML.max_retry_count(snapshots) == 2
    end

    test "returns 0 when all retry counts are nil" do
      snapshots = [%{retry_count: nil}, %{retry_count: nil}]
      assert SnapshotHTML.max_retry_count(snapshots) == 0
    end
  end
end
