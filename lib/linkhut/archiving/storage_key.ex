defmodule Linkhut.Archiving.StorageKey do
  @moduledoc """
  Constructs and parses storage keys that identify stored archive content.

  Storage keys are prefixed strings persisted to the database. The prefix
  determines which backend owns the content:

  - `"local:<path>"` — local filesystem
  - `"external:<url>"` — third-party hosted content (e.g., Wayback Machine)
  - `"s3://<endpoint>/<bucket>/<object_key>"` — S3-compatible object storage
  """

  @type t :: String.t()
  @type parsed ::
          {:local, path :: String.t()}
          | {:external, url :: String.t()}
          | {:s3, rest :: String.t()}

  @spec local(String.t()) :: t()
  def local(path) when is_binary(path), do: "local:" <> path

  @spec external(String.t()) :: t()
  def external(url) when is_binary(url), do: "external:" <> url

  @spec s3(String.t(), String.t(), String.t()) :: t()
  def s3(endpoint, bucket, object_key)
      when is_binary(endpoint) and is_binary(bucket) and is_binary(object_key) do
    "s3://#{endpoint}/#{bucket}/#{object_key}"
  end

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, :invalid_storage_key}
  def parse("local:" <> path), do: {:ok, {:local, path}}
  def parse("external:" <> url), do: {:ok, {:external, url}}
  def parse("s3://" <> rest), do: {:ok, {:s3, rest}}
  def parse(_), do: {:error, :invalid_storage_key}
end
