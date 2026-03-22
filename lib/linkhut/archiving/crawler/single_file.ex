defmodule Linkhut.Archiving.Crawler.SingleFile do
  @moduledoc "Crawler that uses the SingleFile CLI to capture a full page as a single HTML file."

  @behaviour Linkhut.Archiving.Crawler

  alias Linkhut.Archiving.Crawler
  alias Linkhut.Archiving.Crawler.Context

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
  def network_access, do: :target_url

  @impl true
  def queue, do: :crawler

  @html_content_types ~w(text/html application/xhtml+xml)

  # 2 minute timeout for the SingleFile CLI process
  @timeout_ms 120_000
  # Give Chromium 5 seconds to shut down gracefully before SIGKILL
  @delay_to_sigkill 5_000

  @impl true
  def can_handle?(_url, %{content_type: content_type, status: status})
      when content_type in @html_content_types and status < 400 do
    true
  end

  def can_handle?(_url, _preflight_meta), do: false

  @impl true
  def fetch(%Context{link_id: link_id, url: url}) do
    staging_dir =
      Path.join(staging_base_dir(), "linkhut_crawl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)

    args = [
      "--user-agent",
      Crawler.user_agent(),
      url,
      "--filename-template",
      "#{link_id}",
      "--output-directory",
      staging_dir
    ]

    case SingleFile.run(:default, args,
           timeout: @timeout_ms,
           delay_to_sigkill: @delay_to_sigkill
         ) do
      {output, 0} ->
        {:ok,
         {:file,
          %{
            path: Path.join(staging_dir, "#{link_id}"),
            id: link_id,
            code: 0,
            cmd: "single-file",
            args: args,
            content_type: "text/html",
            output: IO.iodata_to_binary(output)
          }}}

      {_output, :timeout} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: "SingleFile timed out after #{@timeout_ms}ms"}}

      {:error, reason} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: reason}}

      {output, code} ->
        Logger.warning("SingleFile exited with code #{code} for #{url}: #{output}")
        File.rm_rf(staging_dir)
        {:error, %{msg: "SingleFile exited with code #{code}"}}
    end
  end

  defp staging_base_dir, do: Linkhut.Config.archiving(:staging_dir, System.tmp_dir!())
end
