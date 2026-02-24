defmodule Linkhut.Archiving.Storage.Local do
  @moduledoc """
  Local filesystem implementation of the Storage behaviour.

  Stores files in a directory structure like:
  `{data_dir}/{user_id}/{link_id}/{type}/{timestamp}/{filename}`

  Returns storage keys prefixed with `local:`, e.g. `local:/tmp/42/1234/singlefile/1735689600/1234`.
  """

  @behaviour Linkhut.Archiving.Storage

  @impl true
  def store({:file, source_path}, user_id, link_id, type) do
    dest_path = build_dest_path(user_id, link_id, type, Path.basename(source_path))
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

  def store({:data, content}, user_id, link_id, type) do
    dest_path = build_dest_path(user_id, link_id, type, "archive")
    File.mkdir_p!(Path.dirname(dest_path))

    case File.write(dest_path, content) do
      :ok -> {:ok, "local:" <> dest_path}
      {:error, reason} -> {:error, reason}
    end
  end

  def store({:stream, stream}, user_id, link_id, type) do
    dest_path = build_dest_path(user_id, link_id, type, "archive")
    File.mkdir_p!(Path.dirname(dest_path))

    file = File.open!(dest_path, [:write, :binary])

    try do
      Enum.each(stream, &IO.binwrite(file, &1))
      File.close(file)
      {:ok, "local:" <> dest_path}
    rescue
      e ->
        File.close(file)
        File.rm(dest_path)
        {:error, e}
    end
  end

  @impl true
  def delete("local:" <> path) do
    if valid_path?(path) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
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

  def resolve(_), do: {:error, :invalid_storage_key}

  @impl true
  def storage_used(opts \\ []) do
    root =
      case Keyword.get(opts, :user_id) do
        nil -> Linkhut.Config.archiving(:data_dir)
        user_id -> Path.join(Linkhut.Config.archiving(:data_dir), "#{user_id}")
      end

    case File.stat(root) do
      {:ok, %{type: :directory}} -> {:ok, dir_size(root)}
      _ -> {:ok, 0}
    end
  end

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

  defp build_dest_path(user_id, link_id, type, filename) do
    timestamp = :os.system_time(:second)

    Path.join([
      Linkhut.Config.archiving(:data_dir),
      "#{user_id}",
      "#{link_id}",
      type,
      "#{timestamp}",
      filename
    ])
  end
end
