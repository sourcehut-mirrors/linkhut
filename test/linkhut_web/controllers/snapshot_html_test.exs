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
    test "returns 'Web page' for singlefile" do
      assert SnapshotHTML.crawler_display_name("singlefile") == "Web page"
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
      assert SnapshotHTML.state_label(:retryable) == "Retrying"
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
      assert SnapshotHTML.state_class(:retryable) == "retryable"
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
    test "extracts from string-keyed crawler_meta" do
      assert SnapshotHTML.crawler_version(%{crawler_meta: %{"version" => "1.0"}}) == "1.0"
    end

    test "returns nil when not available" do
      assert SnapshotHTML.crawler_version(%{crawler_meta: nil}) == nil
    end

    test "returns nil for empty crawler_meta" do
      assert SnapshotHTML.crawler_version(%{crawler_meta: %{}}) == nil
    end
  end

  describe "crawler_label/1" do
    test "returns display name without version" do
      assert SnapshotHTML.crawler_label(%{type: "singlefile", archive_metadata: nil}) ==
               "Web page"
    end

    test "returns display name only (version moved to tool_label)" do
      assert SnapshotHTML.crawler_label(%{
               type: "singlefile",
               archive_metadata: %{"crawler_version" => "1.2.3"}
             }) == "Web page"
    end

    test "handles nil archive_metadata" do
      assert SnapshotHTML.crawler_label(%{type: "singlefile", archive_metadata: nil}) ==
               "Web page"
    end

    test "handles missing type" do
      assert SnapshotHTML.crawler_label(%{archive_metadata: nil}) == "Unknown"
    end

    test "returns File for httpfetch type" do
      assert SnapshotHTML.crawler_label(%{type: "httpfetch", archive_metadata: nil}) ==
               "File"
    end
  end

  describe "tool_name/1" do
    test "extracts tool name from string-keyed crawler_meta" do
      assert SnapshotHTML.tool_name(%{crawler_meta: %{"tool_name" => "Req"}}) == "Req"
    end

    test "returns nil for missing crawler_meta" do
      assert SnapshotHTML.tool_name(%{crawler_meta: nil}) == nil
    end

    test "returns nil for missing tool_name key" do
      assert SnapshotHTML.tool_name(%{crawler_meta: %{}}) == nil
    end
  end

  describe "tool_label/1" do
    test "returns tool name with version" do
      assert SnapshotHTML.tool_label(%{
               type: "httpfetch",
               crawler_meta: %{"tool_name" => "Req", "version" => "0.5.8"}
             }) == "Req 0.5.8"
    end

    test "returns tool name without version" do
      assert SnapshotHTML.tool_label(%{
               type: "httpfetch",
               crawler_meta: %{"tool_name" => "Req"}
             }) == "Req"
    end

    test "falls back to default tool name with version when no tool_name" do
      assert SnapshotHTML.tool_label(%{
               type: "singlefile",
               crawler_meta: %{"version" => "1.2.3"}
             }) == "SingleFile 1.2.3"
    end

    test "returns nil when no tool_name and no version" do
      assert SnapshotHTML.tool_label(%{type: "singlefile", crawler_meta: nil}) == nil
    end
  end

  describe "archive_state_label/1" do
    test "returns labels for known archive states" do
      assert SnapshotHTML.archive_state_label(:pending) == "Queued"
      assert SnapshotHTML.archive_state_label(:processing) == "Processing"
      assert SnapshotHTML.archive_state_label(:complete) == "Complete"
      assert SnapshotHTML.archive_state_label(:failed) == "Failed"
      assert SnapshotHTML.archive_state_label(:pending_deletion) == "Pending deletion"
    end

    test "returns 'Unknown' for unrecognized state" do
      assert SnapshotHTML.archive_state_label(:other) == "Unknown"
    end
  end

  describe "archive_state_class/1" do
    test "returns CSS classes for known archive states" do
      assert SnapshotHTML.archive_state_class(:pending) == "pending"
      assert SnapshotHTML.archive_state_class(:processing) == "processing"
      assert SnapshotHTML.archive_state_class(:complete) == "complete"
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

  describe "step_class/1" do
    test "returns step-failed for failed step" do
      assert SnapshotHTML.step_class(%{"step" => "failed"}) == "step-failed"
    end

    test "returns step-complete for complete step" do
      assert SnapshotHTML.step_class(%{"step" => "complete"}) == "step-complete"
    end

    test "returns step-complete for completed step" do
      assert SnapshotHTML.step_class(%{"step" => "completed"}) == "step-complete"
    end

    test "returns empty string for other steps" do
      assert SnapshotHTML.step_class(%{"step" => "created"}) == ""
    end
  end

  describe "step_display_name/1" do
    test "capitalizes step name" do
      assert SnapshotHTML.step_display_name(%{"step" => "created"}) == "Created"
    end

    test "humanizes underscored step names" do
      assert SnapshotHTML.step_display_name(%{"step" => "head_preflight"}) == "Head preflight"
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
