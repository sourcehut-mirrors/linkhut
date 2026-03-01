defmodule Linkhut.Archiving.Storage do
  @moduledoc """
  Behaviour and abstraction layer for archive storage backends.

  Crawlers produce content in various forms. `store/2` persists it to the
  configured backend (local filesystem, S3, etc.) and returns a `storage_key`
  that identifies the stored content.
  """

  alias Linkhut.Archiving.{Snapshot, StorageKey}
  alias Linkhut.Archiving.Storage.Local

  @typedoc """
  The source of archive content to store.

  - `{:file, path}` — a local file path (e.g., from SingleFile CLI output)
  - `{:data, binary}` — raw binary content
  - `{:stream, enumerable}` — a stream of binary chunks
  """
  @type source :: {:file, Path.t()} | {:data, binary()} | {:stream, Enumerable.t()}

  @doc """
  Persists archive content to the storage backend.

  Returns a `storage_key` that can later be used to retrieve the content.
  """
  @callback store(source(), snapshot :: Snapshot.t()) ::
              {:ok, storage_key :: String.t()} | {:error, term()}

  @typedoc """
  How the stored content should be served to the client.

  - `{:file, path}` — serve directly from the local filesystem
  - `{:redirect, url}` — redirect the client to an external URL (e.g. signed S3-like URL) *(Note: not implemented)*
  """
  @type serve_instruction :: {:file, Path.t()} | {:redirect, String.t()}

  @doc """
  Resolves a storage key into a serve instruction for the controller.
  """
  @callback resolve(storage_key :: String.t()) ::
              {:ok, serve_instruction()} | {:error, term()}

  @doc "Deletes the content identified by the given storage key."
  @callback delete(storage_key :: String.t()) :: :ok | {:error, term()}

  @doc "Returns the total bytes stored on the backend, optionally scoped to a user."
  @callback storage_used(opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}

  def store(source, %Snapshot{} = snapshot) do
    storage_module().store(source, snapshot)
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

      {:error, _} ->
        {:error, :invalid_storage_key}
    end
  end

  def delete(key) do
    case StorageKey.parse(key) do
      {:ok, {:local, _}} -> Local.delete(key)
      {:ok, {:external, _}} -> :ok
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
