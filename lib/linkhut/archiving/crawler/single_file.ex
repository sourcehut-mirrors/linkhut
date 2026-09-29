defmodule Linkhut.Archiving.Crawler.SingleFile do
  @moduledoc "Crawler that uses the SingleFile CLI to capture a full page as a single HTML file."

  @behaviour Linkhut.Archiving.Crawler
  @behaviour Linkhut.Archiving.Crawler.Direct

  alias Linkhut.Archiving.Crawler
  alias Linkhut.Archiving.{Log, PreflightMeta}

  require Logger

  @impl true
  def source_type, do: "singlefile"

  @impl true
  def module_version, do: "1"

  @impl true
  def meta,
    do: %{
      tool_name: "SingleFile",
      tool_version: SingleFile.configured_version(),
      version: module_version()
    }

  @impl true
  def applies_to, do: [schemes: ["http", "https"], hosts: :any, except_hosts: []]

  @impl true
  def queue, do: :crawler

  # 5 minute timeout for the SingleFile CLI process
  @timeout_ms 300_000
  # Give Chromium 1 minute to shut down gracefully before SIGKILL
  @delay_to_sigkill_ms 60_000

  @impl true
  def accepts(_url, %PreflightMeta{status: status, content_type: content_type}) do
    cond do
      status >= 400 ->
        {:reject, %{reason: :http_error, status: status}}

      Linkhut.Archiving.MIME.format(content_type) != "webpage" ->
        {:reject, %{reason: :unsupported_format}}

      true ->
        {:ok, "webpage"}
    end
  end

  @impl true
  def fetch(url, opts) do
    staging_dir = Keyword.fetch!(opts, :staging_dir)

    args = [
      "--user-agent",
      Crawler.user_agent(),
      url,
      "--filename-template",
      "snapshot",
      "--output-directory",
      staging_dir
    ]

    case SingleFile.run(:default, args,
           timeout: @timeout_ms,
           delay_to_sigkill: @delay_to_sigkill_ms
         ) do
      {output, 0} ->
        {:ok,
         {:file,
          %{
            path: Path.join(staging_dir, "snapshot"),
            code: 0,
            cmd: "single-file",
            args: args,
            content_type: "text/html",
            output: IO.iodata_to_binary(output)
          }}}

      {_output, :timeout} ->
        {:error, %{msg: "SingleFile timed out after #{@timeout_ms}ms"}}

      {:error, reason} ->
        {:error, %{msg: reason}}

      {output, code} ->
        Logger.warning("SingleFile exited with code #{code} for #{url}: #{output}")
        Log.append(opts[:log], "singlefile.exited", %{code: code}, level: :warning)
        {:error, %{msg: "SingleFile exited with code #{code}"}}
    end
  end
end
