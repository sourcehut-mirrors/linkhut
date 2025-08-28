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
end
