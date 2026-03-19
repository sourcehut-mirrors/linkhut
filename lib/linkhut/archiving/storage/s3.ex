defmodule Linkhut.Archiving.Storage.S3 do
  @moduledoc """
  S3-compatible object storage backend.

  Stores archive content in an S3-compatible bucket and serves it via
  presigned URLs. Storage keys encode the endpoint, bucket, and object key
  so snapshots survive bucket or provider migrations.

  ## Configuration

      config :linkhut, Linkhut.Archiving.Storage.S3,
        bucket: "linkhut-archives",
        region: "eu-central-1",
        endpoint: "s3.amazonaws.com",
        access_key_id: "...",
        secret_access_key: "...",
        scheme: "https://",
        port: 443,
        presign_ttl: 900,
        compression: :gzip
  """

  alias Linkhut.Archiving.{Snapshot, StorageKey}
  alias Linkhut.Archiving.Storage.Compression
  alias Linkhut.Config

  @behaviour Linkhut.Archiving.Storage

  @chunk_size 5 * 1024 * 1024

  @impl true
  def store(source, snapshot, opts \\ [])

  @impl true
  def store(source, %Snapshot{} = snapshot, opts) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    object_key = build_object_key(snapshot)

    case prepare_upload(source, content_type) do
      {:ok, upload_source, encoding, file_size} ->
        bucket_config = active_bucket_config()

        case do_upload(bucket_config, object_key, upload_source, content_type, encoding) do
          {:ok, _} ->
            storage_key =
              StorageKey.s3(bucket_config[:endpoint], bucket_config[:bucket], object_key)

            {:ok, storage_key, %{file_size_bytes: file_size, encoding: encoding}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def resolve("s3://" <> rest) do
    with {:ok, endpoint, bucket, object_key} <- parse_s3_uri(rest),
         {:ok, bucket_config} <- resolve_bucket_config(endpoint, bucket) do
      presign_url(bucket_config, object_key, [])
    end
  end

  @impl true
  def resolve(_), do: {:error, :invalid_storage_key}

  @impl true
  def resolve("s3://" <> rest, opts) do
    with {:ok, endpoint, bucket, object_key} <- parse_s3_uri(rest),
         {:ok, bucket_config} <- resolve_bucket_config(endpoint, bucket) do
      query_params =
        case Keyword.get(opts, :disposition) do
          nil -> []
          disp -> [{"response-content-disposition", disp}]
        end

      presign_url(bucket_config, object_key, query_params)
    end
  end

  def resolve(_, _opts), do: {:error, :invalid_storage_key}

  @impl true
  def delete("s3://" <> rest) do
    with {:ok, endpoint, bucket, object_key} <- parse_s3_uri(rest),
         {:ok, bucket_config} <- resolve_bucket_config(endpoint, bucket) do
      bucket_config[:bucket]
      |> ExAws.S3.delete_object(object_key)
      |> aws_request(ex_aws_config(bucket_config))
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def delete(_), do: {:error, :invalid_storage_key}

  @impl true
  def storage_used(opts \\ []) do
    bucket_config = active_bucket_config()
    prefix = build_prefix(opts)

    total =
      bucket_config[:bucket]
      |> ExAws.S3.list_objects_v2(prefix: prefix)
      |> aws_stream!(ex_aws_config(bucket_config))
      |> Enum.reduce(0, fn obj, acc -> acc + String.to_integer(obj.size) end)

    {:ok, total}
  rescue
    e -> {:error, e}
  end

  defp prepare_upload({:file, path}, content_type) do
    if should_compress?(content_type) do
      with {:ok, data} <- File.read(path) do
        apply_compression(data)
      end
    else
      case File.stat(path) do
        {:ok, %{size: size}} ->
          {:ok, {:file, path}, nil, size}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp prepare_upload({:data, data}, content_type) do
    if should_compress?(content_type) do
      apply_compression(data)
    else
      {:ok, {:data, data}, nil, byte_size(data)}
    end
  end

  defp prepare_upload({:stream, stream}, content_type) do
    data = Enum.into(stream, <<>>)
    prepare_upload({:data, data}, content_type)
  end

  defp should_compress?(content_type) do
    compression = Config.all(__MODULE__) |> Keyword.get(:compression, :gzip)
    Compression.should_compress?(compression, content_type: content_type)
  end

  defp apply_compression(data) do
    case Compression.compress(data) do
      {:compressed, compressed, size} ->
        {:ok, {:data, compressed}, "gzip", size}

      {:uncompressed, original, size} ->
        {:ok, {:data, original}, nil, size}
    end
  end

  defp do_upload(bucket_config, object_key, body, content_type, encoding) do
    s3_opts =
      [content_type: content_type]
      |> maybe_add_encoding(encoding)

    body
    |> to_upload_stream()
    |> ExAws.S3.upload(bucket_config[:bucket], object_key, s3_opts)
    |> aws_request(ex_aws_config(bucket_config))
  end

  defp to_upload_stream({:file, path}) do
    File.stream!(path, @chunk_size)
  end

  defp to_upload_stream({:data, data}) do
    chunk_binary(data, @chunk_size)
  end

  defp chunk_binary(data, chunk_size) when byte_size(data) <= chunk_size, do: [data]

  defp chunk_binary(data, chunk_size) do
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    [chunk | chunk_binary(rest, chunk_size)]
  end

  defp maybe_add_encoding(opts, nil), do: opts
  defp maybe_add_encoding(opts, encoding), do: Keyword.put(opts, :content_encoding, encoding)

  defp presign_url(bucket_config, object_key, query_params) do
    presign_ttl = Config.all(__MODULE__) |> Keyword.get(:presign_ttl, 900)
    config = ExAws.Config.new(:s3, ex_aws_config(bucket_config))

    presign_opts =
      [expires_in: presign_ttl]
      |> maybe_add_query_params(query_params)

    case ExAws.S3.presigned_url(config, :get, bucket_config[:bucket], object_key, presign_opts) do
      {:ok, url} -> {:ok, {:redirect, url}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_add_query_params(opts, []), do: opts
  defp maybe_add_query_params(opts, params), do: Keyword.put(opts, :query_params, params)

  defp build_object_key(%Snapshot{
         id: id,
         user_id: user_id,
         link_id: link_id,
         format: format
       })
       when is_integer(id) and is_integer(user_id) and is_integer(link_id) and
              is_binary(format) do
    Path.join([
      Integer.to_string(user_id),
      Integer.to_string(link_id),
      "#{id}.#{format}"
    ])
  end

  defp build_prefix(opts) do
    parts =
      [:user_id, :link_id]
      |> Enum.reduce_while([], fn key, acc ->
        case Keyword.get(opts, key) do
          nil -> {:halt, acc}
          val -> {:cont, acc ++ [Integer.to_string(val)]}
        end
      end)

    case parts do
      [] -> nil
      parts -> Enum.join(parts, "/") <> "/"
    end
  end

  defp parse_s3_uri(rest) do
    case String.split(rest, "/", parts: 3) do
      [endpoint, bucket, object_key] when endpoint != "" and bucket != "" and object_key != "" ->
        {:ok, endpoint, bucket, object_key}

      _ ->
        {:error, :invalid_storage_key}
    end
  end

  defp active_bucket_config do
    config = Config.all(__MODULE__)

    case config[:endpoint] do
      nil -> Keyword.put(config, :endpoint, default_endpoint(config[:region]))
      _ -> config
    end
  end

  defp resolve_bucket_config(endpoint, bucket) do
    active = active_bucket_config()

    if active[:endpoint] == endpoint and active[:bucket] == bucket do
      {:ok, active}
    else
      case find_legacy_bucket(endpoint, bucket) do
        nil -> {:error, :unknown_bucket}
        config -> {:ok, config}
      end
    end
  end

  defp find_legacy_bucket(endpoint, bucket) do
    Config.all(__MODULE__)
    |> Keyword.get(:legacy_buckets, [])
    |> Enum.find(fn config ->
      config[:endpoint] == endpoint and config[:bucket] == bucket
    end)
  end

  defp default_endpoint(region) do
    "s3.#{region || "eu-central-1"}.amazonaws.com"
  end

  defp ex_aws_config(bucket_config) do
    base = [
      access_key_id: bucket_config[:access_key_id],
      secret_access_key: bucket_config[:secret_access_key],
      region: bucket_config[:region] || "eu-central-1"
    ]

    base
    |> maybe_add_endpoint(bucket_config)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp maybe_add_endpoint(config, bucket_config) do
    case bucket_config[:endpoint] do
      nil ->
        config

      endpoint ->
        scheme = bucket_config[:scheme] || "https://"
        port = bucket_config[:port] || if(scheme == "https://", do: 443, else: 80)

        config
        |> Keyword.put(:host, endpoint)
        |> Keyword.put(:scheme, scheme)
        |> Keyword.put(:port, port)
    end
  end

  defp aws_request(operation, config) do
    aws_module().request(operation, config)
  end

  defp aws_stream!(operation, config) do
    aws_module().stream!(operation, config)
  end

  defp aws_module do
    Config.all(__MODULE__) |> Keyword.get(:aws_module, ExAws)
  end
end
