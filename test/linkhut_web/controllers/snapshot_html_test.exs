defmodule LinkhutWeb.SnapshotHTMLTest do
  use ExUnit.Case, async: true

  alias LinkhutWeb.SnapshotHTML

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
      assert SnapshotHTML.crawler_version(%{crawler_meta: %{"tool_version" => "1.0"}}) == "1.0"
      assert SnapshotHTML.crawler_version(%{crawler_meta: nil}) == nil
    end

    test "extracts tool_name from crawler_meta" do
      assert SnapshotHTML.tool_name(%{crawler_meta: %{"tool_name" => "Req"}}) == "Req"
      assert SnapshotHTML.tool_name(%{crawler_meta: nil}) == nil
    end
  end

  describe "tool_label/1" do
    test "returns tool name with version" do
      assert SnapshotHTML.tool_label(%{
               source: "httpfetch",
               crawler_meta: %{"tool_name" => "Req", "tool_version" => "0.5.8"}
             }) == "Req 0.5.8"
    end

    test "returns tool name without version" do
      assert SnapshotHTML.tool_label(%{
               source: "httpfetch",
               crawler_meta: %{"tool_name" => "Req"}
             }) == "Req"
    end

    test "falls back to default tool name with version when no tool_name" do
      assert SnapshotHTML.tool_label(%{
               source: "singlefile",
               crawler_meta: %{"tool_version" => "1.2.3"}
             }) == "SingleFile 1.2.3"
    end

    test "returns nil when no tool_name and no version" do
      assert SnapshotHTML.tool_label(%{source: "singlefile", crawler_meta: nil}) == nil
    end
  end

  describe "format_step_time/2" do
    test "formats ISO 8601 timestamp to HH:MM:SS" do
      assert SnapshotHTML.format_step_time("2026-02-26T14:30:45Z", "UTC") == "14:30:45"
    end

    test "returns raw string for invalid timestamp" do
      assert SnapshotHTML.format_step_time("not-a-date", "UTC") == "not-a-date"
    end
  end

  describe "step_display_name/1" do
    test "humanizes underscored step names" do
      assert SnapshotHTML.step_display_name(%{"step" => "head_preflight"}) == "Head preflight"
    end
  end

  describe "wayback_timestamp/2" do
    test "formats valid 14-digit timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "20250301120000"}}
      assert SnapshotHTML.wayback_timestamp(snapshot, "UTC") == "2025-03-01"
    end

    test "formats timestamp longer than 14 digits" do
      snapshot = %{archive_metadata: %{"timestamp" => "20250301120000123"}}
      assert SnapshotHTML.wayback_timestamp(snapshot, "UTC") == "2025-03-01"
    end

    test "returns raw string for non-numeric timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "2025XX01120000"}}
      assert SnapshotHTML.wayback_timestamp(snapshot, "UTC") == "2025XX01120000"
    end

    test "returns raw string for too-short timestamp" do
      snapshot = %{archive_metadata: %{"timestamp" => "2025"}}
      assert SnapshotHTML.wayback_timestamp(snapshot, "UTC") == "2025"
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
