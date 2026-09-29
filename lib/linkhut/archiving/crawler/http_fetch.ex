defmodule Linkhut.Archiving.Crawler.HttpFetch do
  @moduledoc """
  Crawler that downloads files directly via HTTP.

  Handles content types that aren't HTML pages (PDF, plain text, JSON, etc.)
  by streaming the response body to disk with byte counting and size limits.
  """

  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  alias Linkhut.Archiving.{Crawler, MIME, PreflightMeta}
  alias Req.Response

  @tool_name "Req"
  @allowed_types_default [:pdf, :text, :json]
  @overall_timeout_ms 300_000

  @impl true
  def source_type, do: "httpfetch"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta, do: %{tool_name: @tool_name, tool_version: req_version(), version: module_version()}

  @impl true
  def applies_to, do: [schemes: ["http", "https"], hosts: :any, except_hosts: []]

  @impl true
  def queue, do: :crawler

  @impl true
  def accepts(_url, %PreflightMeta{} = meta) do
    format = MIME.format(meta.content_type)

    cond do
      meta.status >= 400 ->
        {:reject, %{reason: :http_error, status: meta.status}}

      format not in allowed_formats() ->
        {:reject, %{reason: :unsupported_format}}

      is_integer(meta.content_length) and meta.content_length > max_bytes() ->
        {:reject, %{reason: :file_too_large, content_length: meta.content_length}}

      true ->
        {:ok, format}
    end
  end

  @impl true
  def fetch(url, opts) do
    path = opts |> Keyword.fetch!(:staging_dir) |> Path.join("download")
    format = Keyword.fetch!(opts, :format)
    task = Task.async(fn -> download(url, path, format) end)

    case Task.yield(task, @overall_timeout_ms) || Task.shutdown(task, 5_000) do
      {:ok, result} ->
        result

      nil ->
        {:error, %{msg: "download timed out after #{@overall_timeout_ms}ms"}}
    end
  end

  defp download(url, path, format) do
    case File.open(path, [:write, :raw], &request(url, &1)) do
      {:ok, {:ok, response}} ->
        process_response(path, format, response)

      {:ok, {:error, reason}} ->
        {:error, %{msg: "download failed: #{inspect(reason)}"}}

      {:error, reason} ->
        {:error, %{msg: "failed to open staging file: #{inspect(reason)}"}}
    end
  end

  defp request(url, file) do
    max = max_bytes()

    [
      url: url,
      method: :get,
      redirect: false,
      retry: false,
      receive_timeout: 60_000,
      into: &write_chunk(file, max, &1, &2),
      raw: true,
      headers: [user_agent: Crawler.user_agent()]
    ]
    |> Keyword.merge(Application.get_env(:linkhut, :req_options, []))
    |> Req.request()
  end

  defp write_chunk(file, max, {:data, chunk}, {req, resp}) do
    size = byte_size(chunk)
    resp = Response.update_private(resp, :bytes, size, &(&1 + size))

    case :file.write(file, chunk) do
      :ok ->
        if Response.get_private(resp, :bytes) > max,
          do: {:halt, {req, resp}},
          else: {:cont, {req, resp}}

      {:error, _reason} ->
        {:halt, {req, Response.put_private(resp, :write_error, true)}}
    end
  end

  defp process_response(path, format, %Response{status: status} = response) do
    cond do
      Response.get_private(response, :write_error) ->
        {:error, %{msg: "disk write error during download"}}

      status not in 200..299 ->
        {:error, %{msg: "HTTP #{status}", response_code: status}}

      true ->
        case verify_content(path, format) do
          :ok ->
            {:ok,
             {:file, %{path: path, response_code: status, content_type: content_type(response)}}}

          {:error, reason} ->
            {:error, %{msg: "content verification failed: #{reason}"}}
        end
    end
  end

  defp content_type(response) do
    response
    |> Response.get_header("content-type")
    |> List.first()
    |> MIME.media_type()
  end

  defp verify_content(path, format) do
    case MIME.detect(path) do
      {:ok, detected_type} ->
        if MIME.format(detected_type) == format,
          do: :ok,
          else: {:error, "not a valid #{format} file (mime-type: #{detected_type})"}

      {:error, reason} ->
        {:error, "cannot validate file: #{inspect(reason)}"}
    end
  end

  defp allowed_formats do
    Linkhut.Config.archiving(:direct_file, [])
    |> Keyword.get(:allowed_types, @allowed_types_default)
    |> Enum.map(&to_string/1)
  end

  defp max_bytes do
    Linkhut.Config.archiving(:max_file_size)
  end

  defp req_version do
    case Application.spec(:req, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
