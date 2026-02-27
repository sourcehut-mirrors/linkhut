defmodule Linkhut.Archiving.Crawler.HttpFetch do
  @moduledoc """
  Crawler that downloads files directly via HTTP.

  Handles content types that aren't HTML pages (PDF, plain text, JSON, etc.)
  by streaming the response body to disk with byte counting and size limits.
  """

  @behaviour Linkhut.Archiving.Crawler

  alias Linkhut.Archiving.Crawler
  alias Linkhut.Archiving.Crawler.Context

  require Logger

  @tool_name "Req"
  @allowed_types_default ["application/pdf", "text/plain", "application/json"]
  @overall_timeout_ms 300_000

  @impl true
  def type, do: "httpfetch"

  @impl true
  def meta, do: %{tool_name: @tool_name, version: req_version()}

  @impl true
  def can_handle?(_url, preflight_meta) do
    content_type = Map.get(preflight_meta, :content_type)
    content_length = Map.get(preflight_meta, :content_length)

    content_type in allowed_types() and
      (not is_integer(content_length) or content_length <= max_bytes())
  end

  @impl true
  def fetch(%Context{url: url, link_id: link_id, preflight_meta: preflight_meta}) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_httpfetch_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)
    path = Path.join(staging_dir, "#{link_id}")

    expected_content_type =
      case preflight_meta do
        %{content_type: ct} when is_binary(ct) -> ct
        _ -> nil
      end

    task =
      Task.async(fn ->
        do_download(url, path, expected_content_type)
      end)

    case Task.yield(task, @overall_timeout_ms) || Task.shutdown(task, 5_000) do
      {:ok, result} ->
        result

      nil ->
        File.rm_rf(staging_dir)
        {:error, %{msg: "download timed out after #{@overall_timeout_ms}ms"}}
    end
  end

  defp do_download(url, path, expected_content_type) do
    case File.open(path, [:write, :raw]) do
      {:ok, file} ->
        stream_and_process(url, path, expected_content_type, file)

      {:error, reason} ->
        {:error, %{msg: "failed to open staging file: #{inspect(reason)}"}}
    end
  end

  defp stream_and_process(url, path, expected_content_type, file) do
    Process.delete(:httpfetch_write_error)
    max = max_bytes()
    staging_dir = Path.dirname(path)
    byte_counter = :counters.new(1, [:atomics])

    into_fun = build_stream_handler(file, byte_counter, max)
    req_opts = build_req_opts(url, into_fun)

    result =
      case Req.request(Req.new(req_opts)) do
        {:ok, %Req.Response{status: status}} ->
          total_bytes = :counters.get(byte_counter, 1)
          has_write_error = Process.get(:httpfetch_write_error, false)
          process_response(path, expected_content_type, status, total_bytes, max, has_write_error)

        {:error, reason} ->
          {:error, %{msg: "download failed: #{inspect(reason)}"}}
      end

    File.close(file)

    case result do
      {:ok, _} ->
        result

      {:error, _} ->
        File.rm_rf(staging_dir)
        result
    end
  end

  defp build_stream_handler(file, byte_counter, max) do
    fn {:data, chunk}, {req, resp} ->
      :counters.add(byte_counter, 1, byte_size(chunk))

      case :file.write(file, chunk) do
        :ok -> :ok
        {:error, _} -> Process.put(:httpfetch_write_error, true)
      end

      if Process.get(:httpfetch_write_error) || :counters.get(byte_counter, 1) > max do
        {:halt, {req, resp}}
      else
        {:cont, {req, resp}}
      end
    end
  end

  defp build_req_opts(url, into_fun) do
    # Redirects disabled — we use the SSRF-checked final_url from preflight.
    [
      url: url,
      method: :get,
      redirect: false,
      retry: false,
      receive_timeout: 60_000,
      into: into_fun,
      raw: true,
      headers: [user_agent: Crawler.user_agent()]
    ]
    |> Keyword.merge(Application.get_env(:linkhut, :req_options, []))
  end

  defp process_response(_path, _ct, _status, _total_bytes, _max, true = _has_write_error) do
    {:error, %{msg: "disk write error during download"}}
  end

  defp process_response(_path, _ct, _status, total_bytes, max, _has_write_error)
       when total_bytes > max do
    {:error, %{msg: "file exceeds max size (#{max} bytes)"}}
  end

  defp process_response(_path, _ct, status, _total_bytes, _max, _has_write_error)
       when status not in 200..299 do
    {:error, %{msg: "HTTP #{status}", response_code: status}}
  end

  defp process_response(path, expected_content_type, status, _total_bytes, _max, _has_write_error) do
    case verify_content(path, expected_content_type) do
      :ok ->
        {:ok,
         %{
           path: path,
           response_code: status,
           content_type: expected_content_type
         }}

      {:error, reason} ->
        {:error, %{msg: "content verification failed: #{reason}"}}
    end
  end

  @doc false
  def verify_content(path, content_type) do
    case content_type do
      "application/pdf" -> verify_pdf(path)
      "application/json" -> verify_json(path)
      "text/" <> _ -> verify_text(path)
      _ -> :ok
    end
  end

  defp verify_pdf(path) do
    case File.open(path, [:read, :raw]) do
      {:ok, file} ->
        header = IO.binread(file, 5)
        File.close(file)

        if header == "%PDF-" do
          :ok
        else
          {:error, "not a valid PDF (missing %PDF- header)"}
        end

      {:error, reason} ->
        {:error, "cannot read file: #{inspect(reason)}"}
    end
  end

  defp verify_json(path) do
    case File.open(path, [:read, :raw, :binary]) do
      {:ok, file} ->
        chunk = IO.binread(file, 4096)
        File.close(file)

        chunk =
          if is_binary(chunk), do: String.trim_leading(chunk), else: ""

        if String.starts_with?(chunk, "{") or String.starts_with?(chunk, "[") do
          :ok
        else
          {:error, "not valid JSON (first non-whitespace char is not { or [)"}
        end

      {:error, reason} ->
        {:error, "cannot read file: #{inspect(reason)}"}
    end
  end

  defp verify_text(path) do
    case File.open(path, [:read, :raw, :binary]) do
      {:ok, file} ->
        chunk = IO.binread(file, 4096)
        File.close(file)

        if is_binary(chunk) and String.valid?(chunk) do
          :ok
        else
          {:error, "content is not valid UTF-8 text"}
        end

      {:error, reason} ->
        {:error, "cannot read file: #{inspect(reason)}"}
    end
  end

  defp allowed_types do
    Linkhut.Config.get(
      [Linkhut, :archiving, :direct_file, :allowed_types],
      @allowed_types_default
    )
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
