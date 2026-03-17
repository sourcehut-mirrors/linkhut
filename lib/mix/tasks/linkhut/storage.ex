defmodule Mix.Tasks.Linkhut.Storage do
  use Mix.Task

  import Ecto.Query
  import Mix.Linkhut

  alias Linkhut.Archiving
  alias Linkhut.Archiving.{Snapshot, Storage, StorageKey}
  alias Linkhut.Archiving.Storage.Local
  alias Linkhut.Repo

  @moduledoc """
  Archiving storage management.

  ## Usage

      mix linkhut.storage                                  # Show storage stats
      mix linkhut.storage local.compress [--dry-run]       # Gzip-compress uncompressed local snapshots
      mix linkhut.storage local.decompress [--dry-run]     # Decompress gzip-compressed local snapshots
  """

  @shortdoc "Archiving storage management"

  def run([]) do
    start_linkhut()
    show_stats()
  end

  def run(["local.compress" | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [dry_run: :boolean, batch_size: :integer])

    start_linkhut()
    compress(opts)
  end

  def run(["local.decompress" | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [dry_run: :boolean, batch_size: :integer])

    start_linkhut()
    decompress(opts)
  end

  def run(_) do
    shell_error("""
    Usage:
      mix linkhut.storage                                  # Show storage stats
      mix linkhut.storage local.compress [--dry-run]       # Compress snapshots
      mix linkhut.storage local.decompress [--dry-run]     # Decompress snapshots
    """)
  end

  defp show_stats do
    db_bytes = Archiving.storage_used()
    {:ok, disk_bytes} = Storage.storage_used()

    shell_info("Storage (DB total):   #{Linkhut.Formatting.format_bytes(db_bytes)}")
    shell_info("Storage (disk total): #{Linkhut.Formatting.format_bytes(disk_bytes)}")
  end

  # -- compress --

  defp compress(opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    batch_size = Keyword.get(opts, :batch_size, 100)

    if dry_run?, do: shell_info("=== DRY RUN ===\n")

    {count, failures, saved} = compress_loop(0, batch_size, dry_run?, 0, 0, 0)

    shell_info(
      "\nDone. Compressed: #{count}, Failed: #{failures}, Saved: #{Linkhut.Formatting.format_bytes(saved)}"
    )
  end

  defp compress_loop(last_id, batch_size, dry_run?, count, failures, saved) do
    compressible_types = Local.compressible_types()

    snapshots =
      from(s in Snapshot,
        where: s.id > ^last_id,
        where: s.state == :complete,
        where: is_nil(s.encoding),
        where: like(s.storage_key, "local:%"),
        where:
          fragment(
            "? ->> 'content_type' = ANY(?)",
            s.archive_metadata,
            ^compressible_types
          ),
        order_by: [asc: s.id],
        limit: ^batch_size
      )
      |> Repo.all()

    if snapshots == [] do
      {count, failures, saved}
    else
      {batch_count, batch_failures, batch_saved} = compress_batch(snapshots, dry_run?)

      new_last_id = List.last(snapshots).id

      compress_loop(
        new_last_id,
        batch_size,
        dry_run?,
        count + batch_count,
        failures + batch_failures,
        saved + batch_saved
      )
    end
  end

  defp compress_batch(snapshots, dry_run?) do
    Enum.reduce(snapshots, {0, 0, 0}, fn snapshot, {c, f, s} ->
      case compress_snapshot(snapshot, dry_run?) do
        {:ok, saved_bytes} -> {c + 1, f, s + saved_bytes}
        :error -> {c, f + 1, s}
      end
    end)
  end

  defp compress_snapshot(snapshot, dry_run?) do
    with {:ok, path} <- parse_local_key(snapshot),
         {:ok, original_size} <- read_file_size(snapshot, path) do
      compress_local_file(snapshot, path, original_size, dry_run?)
    end
  end

  defp compress_local_file(snapshot, path, original_size, dry_run?) do
    compressed = :zlib.gzip(File.read!(path))
    compressed_size = byte_size(compressed)

    if compressed_size >= original_size do
      shell_info("  ##{snapshot.id}: skipped (compressed not smaller)")
      {:ok, 0}
    else
      saved_bytes = original_size - compressed_size
      ratio = Float.round(compressed_size / max(original_size, 1) * 100, 1)

      shell_info(
        "  ##{snapshot.id}: #{Linkhut.Formatting.format_bytes(original_size)} -> " <>
          "#{Linkhut.Formatting.format_bytes(compressed_size)} (#{ratio}%)"
      )

      if dry_run? do
        {:ok, saved_bytes}
      else
        persist_compressed(
          snapshot,
          path,
          compressed,
          compressed_size,
          original_size,
          saved_bytes
        )
      end
    end
  end

  defp persist_compressed(snapshot, path, compressed, compressed_size, original_size, saved_bytes) do
    dest_gz = path <> ".gz"

    with :ok <- File.write(dest_gz, compressed),
         {:ok, _} <-
           Archiving.update_snapshot(snapshot, %{
             storage_key: StorageKey.local(dest_gz),
             encoding: "gzip",
             file_size_bytes: compressed_size,
             original_file_size_bytes: original_size
           }) do
      File.rm(path)
      Archiving.recompute_crawl_run_size_by_id(snapshot.crawl_run_id)
      {:ok, saved_bytes}
    else
      {:error, reason} when is_atom(reason) ->
        shell_error("  ##{snapshot.id}: Write failed: #{inspect(reason)}")
        :error

      {:error, changeset} ->
        File.rm(dest_gz)
        shell_error("  ##{snapshot.id}: DB update failed: #{inspect(changeset.errors)}")
        :error
    end
  end

  # -- decompress --

  defp decompress(opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    batch_size = Keyword.get(opts, :batch_size, 100)

    if dry_run?, do: shell_info("=== DRY RUN ===\n")

    {count, failures} = decompress_loop(0, batch_size, dry_run?, 0, 0)

    shell_info("\nDone. Decompressed: #{count}, Failed: #{failures}")
  end

  defp decompress_loop(last_id, batch_size, dry_run?, count, failures) do
    snapshots =
      from(s in Snapshot,
        where: s.id > ^last_id,
        where: s.state == :complete,
        where: s.encoding == "gzip",
        where: like(s.storage_key, "local:%"),
        order_by: [asc: s.id],
        limit: ^batch_size
      )
      |> Repo.all()

    if snapshots == [] do
      {count, failures}
    else
      {batch_count, batch_failures} = decompress_batch(snapshots, dry_run?)

      new_last_id = List.last(snapshots).id

      decompress_loop(
        new_last_id,
        batch_size,
        dry_run?,
        count + batch_count,
        failures + batch_failures
      )
    end
  end

  defp decompress_batch(snapshots, dry_run?) do
    Enum.reduce(snapshots, {0, 0}, fn snapshot, {c, f} ->
      case decompress_snapshot(snapshot, dry_run?) do
        :ok -> {c + 1, f}
        :error -> {c, f + 1}
      end
    end)
  end

  defp decompress_snapshot(snapshot, dry_run?) do
    with {:ok, path} <- parse_local_key(snapshot),
         {:ok, compressed} <- read_gzip_file(snapshot, path) do
      decompress_local_file(snapshot, path, compressed, dry_run?)
    end
  end

  defp read_gzip_file(snapshot, path) do
    case File.read(path) do
      {:ok, <<0x1F, 0x8B, _::binary>>} = ok ->
        ok

      {:ok, _} ->
        shell_error("  ##{snapshot.id}: File is not gzip (bad magic bytes), skipping")
        :error

      {:error, reason} ->
        shell_error("  ##{snapshot.id}: File not found (#{inspect(reason)}): #{path}")
        :error
    end
  end

  defp decompress_local_file(snapshot, path, compressed, dry_run?) do
    decompressed = :zlib.gunzip(compressed)
    decompressed_size = byte_size(decompressed)

    shell_info(
      "  ##{snapshot.id}: #{Linkhut.Formatting.format_bytes(File.stat!(path).size)} -> " <>
        "#{Linkhut.Formatting.format_bytes(decompressed_size)}"
    )

    if dry_run? do
      :ok
    else
      persist_decompressed(snapshot, path, decompressed, decompressed_size)
    end
  end

  defp persist_decompressed(snapshot, path, decompressed, decompressed_size) do
    dest_path = String.replace_suffix(path, ".gz", "")

    with :ok <- File.write(dest_path, decompressed),
         {:ok, _} <-
           Archiving.update_snapshot(snapshot, %{
             storage_key: StorageKey.local(dest_path),
             encoding: nil,
             file_size_bytes: decompressed_size,
             original_file_size_bytes: nil
           }) do
      File.rm(path)
      Archiving.recompute_crawl_run_size_by_id(snapshot.crawl_run_id)
      :ok
    else
      {:error, reason} when is_atom(reason) ->
        shell_error("  ##{snapshot.id}: Write failed: #{inspect(reason)}")
        :error

      {:error, changeset} ->
        File.rm(dest_path)
        shell_error("  ##{snapshot.id}: DB update failed: #{inspect(changeset.errors)}")
        :error
    end
  end

  # -- shared helpers --

  defp parse_local_key(snapshot) do
    case StorageKey.parse(snapshot.storage_key) do
      {:ok, {:local, path}} ->
        {:ok, path}

      _ ->
        shell_error("  ##{snapshot.id}: Invalid storage key")
        :error
    end
  end

  defp read_file_size(snapshot, path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        {:ok, size}

      {:error, reason} ->
        shell_error("  ##{snapshot.id}: File not found (#{inspect(reason)}): #{path}")
        :error
    end
  end
end
