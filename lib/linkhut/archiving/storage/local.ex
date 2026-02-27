defmodule Linkhut.Archiving.Storage.Local do
  @moduledoc """
  Local filesystem implementation of the Storage behaviour.

  Stores files in a directory structure like:
  `{data_dir}/{user_id}/{link_id}/{archive_id}/{snapshot_id}.{type}`

  Returns storage keys prefixed with `local:`, e.g. `local:/data/archiving/42/1234/567/890.singlefile`.
  """

  alias Linkhut.Archiving.Snapshot

  @behaviour Linkhut.Archiving.Storage

  @impl true
  def store({:file, source_path}, %Snapshot{} = snapshot) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    case File.rename(source_path, dest_path) do
      :ok ->
        {:ok, "local:" <> dest_path}

      {:error, :exdev} ->
        with {:ok, _} <- File.copy(source_path, dest_path),
             :ok <- File.rm(source_path) do
          {:ok, "local:" <> dest_path}
        end
    end
  end

  @impl true
  def store({:data, content}, %Snapshot{} = snapshot) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    case File.write(dest_path, content) do
      :ok -> {:ok, "local:" <> dest_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def store({:stream, stream}, %Snapshot{} = snapshot) do
    dest_path = build_dest_path(snapshot)
    File.mkdir_p!(Path.dirname(dest_path))

    with {:ok, file} <- File.open(dest_path, [:write, :binary]) do
      try do
        Enum.each(stream, fn chunk ->
          case :file.write(file, chunk) do
            :ok -> :ok
            {:error, reason} -> throw({:write_error, reason})
          end
        end)

        {:ok, "local:" <> dest_path}
      rescue
        e -> {:error, e}
      catch
        {:write_error, reason} -> {:error, reason}
      after
        File.close(file)
      end
    end
    |> case do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        File.rm(dest_path)
        err
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
  # link_id required if archive_id given.
  defp build_storage_root(opts) do
    Linkhut.Config.archiving(:data_dir)
    |> maybe_join(Keyword.get(opts, :user_id))
    |> maybe_join(Keyword.get(opts, :link_id))
    |> maybe_join(Keyword.get(opts, :archive_id))
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
         archive_id: archive_id,
         type: type
       })
       when is_integer(id) and is_integer(user_id) and is_integer(link_id) and
              is_integer(archive_id) and is_binary(type) do
    Path.join([
      Linkhut.Config.archiving(:data_dir),
      Integer.to_string(user_id),
      Integer.to_string(link_id),
      Integer.to_string(archive_id),
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
