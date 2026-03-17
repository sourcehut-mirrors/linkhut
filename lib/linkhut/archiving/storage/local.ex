defmodule Linkhut.Archiving.Storage.Local do
  @moduledoc """
  Local filesystem implementation of the Storage behaviour.

  Stores files in a directory structure like:
  `{data_dir}/{user_id}/{link_id}/{crawl_run_id}/{snapshot_id}.{type}`

  Returns storage keys prefixed with `local:`, e.g. `local:/data/archiving/42/1234/567/890.singlefile`.
  """

  alias Linkhut.Archiving.{Snapshot, StorageKey}

  @behaviour Linkhut.Archiving.Storage

  @compressible_types [
    # HTML / XML
    "text/html",
    "application/xhtml+xml",
    "application/xml",
    "text/xml",
    "application/atom+xml",
    "application/rss+xml",
    # Text
    "text/plain",
    "text/markdown",
    "text/css",
    "text/csv",
    # Script / data
    "text/javascript",
    "application/javascript",
    "application/json",
    "application/ld+json",
    # Other
    "application/rtf",
    "image/svg+xml"
  ]
  def compressible_types, do: @compressible_types

  @impl true
  def store(source, snapshot, opts \\ [])

  @impl true
  def store({:file, source_path}, %Snapshot{} = snapshot, opts) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    if should_compress?(opts) do
      content = File.read!(source_path)

      case store_compressed(content, dest_path) do
        {:ok, _, _} = result ->
          File.rm(source_path)
          result

        error ->
          error
      end
    else
      case move_file(source_path, dest_path) do
        :ok ->
          size = File.stat!(dest_path).size
          {:ok, StorageKey.local(dest_path), %{file_size_bytes: size, encoding: nil}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def store({:data, content}, %Snapshot{} = snapshot, opts) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    if should_compress?(opts) do
      store_compressed(content, dest_path)
    else
      case File.write(dest_path, content) do
        :ok ->
          {:ok, StorageKey.local(dest_path),
           %{file_size_bytes: byte_size(content), encoding: nil}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def store({:stream, stream}, %Snapshot{} = snapshot, opts) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    if should_compress?(opts) do
      content = Enum.into(stream, <<>>)
      store_compressed(content, dest_path)
    else
      with {:ok, file} <- File.open(dest_path, [:write, :binary]) do
        try do
          Enum.each(stream, fn chunk ->
            case :file.write(file, chunk) do
              :ok -> :ok
              {:error, reason} -> throw({:write_error, reason})
            end
          end)

          size = File.stat!(dest_path).size
          {:ok, StorageKey.local(dest_path), %{file_size_bytes: size, encoding: nil}}
        rescue
          e -> {:error, e}
        catch
          {:write_error, reason} -> {:error, reason}
        after
          File.close(file)
        end
      end
      |> case do
        {:ok, _, _} = ok ->
          ok

        {:error, _} = err ->
          File.rm(dest_path)
          err
      end
    end
  end

  @impl true
  def delete("local:" <> path) do
    if valid_path?(path) do
      case File.rm(path) do
        :ok ->
          prune_empty_parents(path)
          :ok

        {:error, :enoent} ->
          prune_empty_parents(path)
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid_storage_key}
    end
  end

  @impl true
  def resolve("local:" <> path) do
    if valid_path?(path) do
      {:ok, {:file, path}}
    else
      {:error, :invalid_storage_key}
    end
  end

  @impl true
  def resolve(_), do: {:error, :invalid_storage_key}

  @impl true
  def storage_used(opts \\ []) do
    root = build_storage_root(opts)

    case File.stat(root) do
      {:ok, %{type: :directory}} -> {:ok, dir_size(root)}
      _ -> {:ok, 0}
    end
  end

  # Opts must be hierarchically complete: user_id required if link_id given,
  # link_id required if crawl_run_id given.
  defp build_storage_root(opts) do
    Linkhut.Config.archiving(:data_dir)
    |> maybe_join(Keyword.get(opts, :user_id))
    |> maybe_join(Keyword.get(opts, :link_id))
    |> maybe_join(Keyword.get(opts, :crawl_run_id))
  end

  defp maybe_join(path, nil), do: path
  defp maybe_join(path, segment), do: Path.join(path, "#{segment}")

  defp dir_size(path) do
    path
    |> File.ls!()
    |> Enum.reduce(0, fn entry, acc ->
      full = Path.join(path, entry)

      case File.lstat(full) do
        {:ok, %{type: :regular, size: size}} -> acc + size
        {:ok, %{type: :directory}} -> acc + dir_size(full)
        _ -> acc
      end
    end)
  end

  defp should_compress?(opts) do
    compression_algo() != :none and
      Keyword.get(opts, :content_type) in @compressible_types
  end

  defp compression_algo do
    Application.get_env(:linkhut, __MODULE__, [])
    |> Keyword.get(:compression, :none)
  end

  defp store_compressed(content, dest_path) do
    compressed = :zlib.gzip(content)

    if byte_size(compressed) >= byte_size(content) do
      case File.write(dest_path, content) do
        :ok ->
          {:ok, StorageKey.local(dest_path),
           %{file_size_bytes: byte_size(content), encoding: nil}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      dest_gz = dest_path <> ".gz"

      case File.write(dest_gz, compressed) do
        :ok ->
          {:ok, StorageKey.local(dest_gz),
           %{file_size_bytes: byte_size(compressed), encoding: "gzip"}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp move_file(source, dest) do
    case File.rename(source, dest) do
      :ok ->
        :ok

      {:error, :exdev} ->
        with {:ok, _} <- File.copy(source, dest) do
          File.rm(source)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp valid_path?(path) do
    expanded = Path.expand(path)

    allowed_dirs = [
      Linkhut.Config.archiving(:data_dir)
      | Linkhut.Config.archiving(:legacy_data_dirs, [])
    ]

    Enum.any?(allowed_dirs, fn dir ->
      String.starts_with?(expanded, Path.expand(dir) <> "/")
    end)
  end

  defp build_dest_path(%Snapshot{
         id: id,
         user_id: user_id,
         link_id: link_id,
         crawl_run_id: crawl_run_id,
         type: type
       })
       when is_integer(id) and is_integer(user_id) and is_integer(link_id) and
              is_integer(crawl_run_id) and is_binary(type) do
    Path.join([
      Linkhut.Config.archiving(:data_dir),
      Integer.to_string(user_id),
      Integer.to_string(link_id),
      Integer.to_string(crawl_run_id),
      "#{id}.#{type}"
    ])
  end

  defp prune_empty_parents(path) do
    data_dir = Path.expand(Linkhut.Config.archiving(:data_dir))
    do_prune(Path.dirname(path), data_dir)
  end

  defp do_prune(dir, boundary) do
    expanded = Path.expand(dir)

    if expanded != boundary and String.starts_with?(expanded, boundary <> "/") do
      case File.rmdir(dir) do
        :ok -> do_prune(Path.dirname(dir), boundary)
        {:error, _} -> :ok
      end
    else
      :ok
    end
  end
end
