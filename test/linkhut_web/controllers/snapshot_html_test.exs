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
    test "formats unknown codes as raw integer" do
      assert SnapshotHTML.format_response_code(418) == "418"
    end
  end

  describe "metadata extraction" do
    test "extracts final_url from archive_metadata" do
      assert SnapshotHTML.final_url(%{archive_metadata: %{"final_url" => "https://example.com"}}) ==
               "https://example.com"

      assert SnapshotHTML.final_url(%{archive_metadata: nil}) == nil
    end

    test "extracts original_url from archive_metadata" do
      assert SnapshotHTML.original_url(%{
               archive_metadata: %{"original_url" => "https://original.com"}
             }) == "https://original.com"

      assert SnapshotHTML.original_url(%{archive_metadata: nil}) == nil
    end

    test "extracts content_type from archive_metadata" do
      assert SnapshotHTML.content_type(%{archive_metadata: %{"content_type" => "text/html"}}) ==
               "text/html"

      assert SnapshotHTML.content_type(%{archive_metadata: nil}) == nil
    end

    test "extracts crawler_version from crawler_meta" do
      assert SnapshotHTML.crawler_version(%{crawler_meta: %{"version" => "1.0"}}) == "1.0"
      assert SnapshotHTML.crawler_version(%{crawler_meta: nil}) == nil
    end

    test "extracts tool_name from crawler_meta" do
      assert SnapshotHTML.tool_name(%{crawler_meta: %{"tool_name" => "Req"}}) == "Req"
      assert SnapshotHTML.tool_name(%{crawler_meta: nil}) == nil
    end
  end

  describe "crawler_label/1" do
    test "returns display name for known type" do
      assert SnapshotHTML.crawler_label(%{type: "singlefile", archive_metadata: nil}) ==
               "Web page"
    end

    test "returns Unknown for missing type" do
      assert SnapshotHTML.crawler_label(%{archive_metadata: nil}) == "Unknown"
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

  describe "crawl_steps/1" do
    test "extracts steps from string-keyed crawl_info" do
      steps = [%{"step" => "fetch", "at" => "2026-02-26T14:30:45Z"}]
      assert SnapshotHTML.crawl_steps(%{crawl_info: %{"steps" => steps}}) == steps
    end

    test "returns empty list for missing crawl_info" do
      assert SnapshotHTML.crawl_steps(%{crawl_info: nil}) == []
      assert SnapshotHTML.crawl_steps(%{}) == []
    end
  end

  describe "step_display_name/1" do
    test "humanizes underscored step names" do
      assert SnapshotHTML.step_display_name(%{"step" => "head_preflight"}) == "Head preflight"
    end
  end

  describe "wayback_timestamp/1" do
    test "formats valid 14-digit timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "20250301120000"}}
      assert SnapshotHTML.wayback_timestamp(snapshot) == "2025-03-01"
    end

    test "formats timestamp longer than 14 digits" do
      snapshot = %{archive_metadata: %{"timestamp" => "20250301120000123"}}
      assert SnapshotHTML.wayback_timestamp(snapshot) == "2025-03-01"
    end

    test "returns raw string for non-numeric timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "2025XX01120000"}}
      assert SnapshotHTML.wayback_timestamp(snapshot) == "2025XX01120000"
    end

    test "returns nil for missing timestamp" do
      assert SnapshotHTML.wayback_timestamp(%{archive_metadata: %{}}) == nil
    end

    test "returns nil for nil archive_metadata" do
      assert SnapshotHTML.wayback_timestamp(%{archive_metadata: nil}) == nil
    end

    test "returns nil for missing archive_metadata field" do
      assert SnapshotHTML.wayback_timestamp(%{}) == nil
    end

    test "returns raw string for too-short timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "2025"}}
      assert SnapshotHTML.wayback_timestamp(snapshot) == "2025"
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
