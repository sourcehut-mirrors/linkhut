defmodule Linkhut.Archiving.Storage do
  @moduledoc """
  Behaviour and abstraction layer for archive storage backends.

  Crawlers produce content in various forms. `store/3` persists it to the
  configured backend (local filesystem, S3, etc.) and returns a `storage_key`
  and metadata that identifies the stored content.
  """

  alias Linkhut.Archiving.{Snapshot, StorageKey}
  alias Linkhut.Archiving.Storage.{Local, S3}

  @typedoc """
  The source of archive content to store.

  - `{:file, path}` — a local file path (e.g., from SingleFile CLI output)
  - `{:data, binary}` — raw binary content
  - `{:stream, enumerable}` — a stream of binary chunks
  """
  @type source :: {:file, Path.t()} | {:data, binary()} | {:stream, Enumerable.t()}

  @typedoc """
  Metadata returned by the storage backend after storing content.

  - `file_size_bytes` — size of the stored file on disk (may differ from original if compressed)
  - `encoding` — content encoding applied during storage (e.g. `"gzip"`), or `nil` if none
  """
  @type store_meta :: %{file_size_bytes: non_neg_integer(), encoding: String.t() | nil}

  @doc """
  Persists archive content to the storage backend.

  Returns a `storage_key` and metadata that can later be used to retrieve the content.
  """
  @callback store(source(), snapshot :: Snapshot.t(), opts :: keyword()) ::
              {:ok, storage_key :: String.t(), store_meta()} | {:error, term()}

  @typedoc """
  How the stored content should be served to the client.

  - `{:file, path}` — serve directly from the local filesystem
  - `{:redirect, url}` — redirect the client to an external URL (e.g. presigned S3 URL)
  """
  @type serve_instruction :: {:file, Path.t()} | {:redirect, String.t()}

  @doc """
  Resolves a storage key into a serve instruction for the controller.
  """
  @callback resolve(storage_key :: String.t()) ::
              {:ok, serve_instruction()} | {:error, term()}

  @doc """
  Resolves a storage key with additional options (e.g. content disposition for downloads).
  """
  @callback resolve(storage_key :: String.t(), opts :: keyword()) ::
              {:ok, serve_instruction()} | {:error, term()}

  @optional_callbacks [resolve: 2]

  @doc "Deletes the content identified by the given storage key."
  @callback delete(storage_key :: String.t()) :: :ok | {:error, term()}

  @doc "Returns the total bytes stored on the backend, optionally scoped to a user."
  @callback storage_used(opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}

  def store(source, %Snapshot{} = snapshot, opts \\ []) do
    storage_module().store(source, snapshot, opts)
  end

  @doc """
  Resolves a storage key by dispatching to the backend that produced it.

  Uses `StorageKey.parse/1` to determine which module handles resolution,
  regardless of the currently configured storage backend.
  """
  def resolve(key) do
    case StorageKey.parse(key) do
      {:ok, {:local, _}} ->
        Local.resolve(key)

      {:ok, {:external, url}} ->
        if valid_external_url?(url),
          do: {:ok, {:redirect, url}},
          else: {:error, :invalid_storage_key}

      {:ok, {:s3, _}} ->
        S3.resolve(key)

      {:error, _} ->
        {:error, :invalid_storage_key}
    end
  end

  @doc """
  Resolves a storage key with additional options.

  Currently only S3 supports options (e.g. `:disposition` for downloads).
  Other backends fall back to `resolve/1`.
  """
  def resolve(key, opts) do
    case StorageKey.parse(key) do
      {:ok, {:s3, _}} -> S3.resolve(key, opts)
      _ -> resolve(key)
    end
  end

  def delete(key) do
    case StorageKey.parse(key) do
      {:ok, {:local, _}} -> Local.delete(key)
      {:ok, {:external, _}} -> :ok
      {:ok, {:s3, _}} -> S3.delete(key)
      {:error, _} -> {:error, :invalid_storage_key}
    end
  end

  defp valid_external_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> true
      _ -> false
    end
  end

  def storage_used(opts \\ []) do
    storage_module().storage_used(opts)
  end

  defp storage_module do
    Linkhut.Config.archiving(:storage, Linkhut.Archiving.Storage.Local)
  end
end
