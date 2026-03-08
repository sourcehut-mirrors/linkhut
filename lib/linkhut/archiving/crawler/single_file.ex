defmodule Linkhut.Archiving.Crawler.SingleFile do
  @moduledoc "Crawler that uses the SingleFile CLI to capture a full page as a single HTML file."

  @behaviour Linkhut.Archiving.Crawler

  alias Linkhut.Archiving.Crawler
  alias Linkhut.Archiving.Crawler.Context

  @impl true
  def type, do: "singlefile"

  @impl true
  def meta, do: %{tool_name: "SingleFile", version: SingleFile.configured_version()}

  @impl true
  def network_access, do: :target_url

  @impl true
  def queue, do: :crawler

  @html_content_types ~w(text/html application/xhtml+xml)

  # 1 minute timeout
  @timeout_ms 60_000

  @impl true
  def can_handle?(_url, %{content_type: content_type, status: status})
      when content_type in @html_content_types and status < 400 do
    true
  end

  def can_handle?(_url, _preflight_meta), do: false

  @impl true
  def fetch(%Context{link_id: link_id, url: url}) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_crawl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)

    task = Task.async(fn -> run_single_file(link_id, url, staging_dir) end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, 5_000) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: "SingleFile crashed: #{inspect(reason)}"}}

      nil ->
        File.rm_rf(staging_dir)
        {:error, %{msg: "SingleFile timed out after #{@timeout_ms}ms"}}
    end
  end

  defp run_single_file(link_id, url, staging_dir) do
    args = [
      "--user-agent",
      Crawler.user_agent(),
      url,
      "--filename-template",
      "#{link_id}",
      "--output-directory",
      staging_dir
    ]

    case SingleFile.run(:default, args) do
      {output, code} when code == 0 ->
        {:ok,
         {:file,
          %{
            path: Path.join(staging_dir, "#{link_id}"),
            id: link_id,
            code: code,
            cmd: "single-file",
            args: args,
            content_type: "text/html",
            output: IO.iodata_to_binary(output)
          }}}

      {:error, reason} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: reason}}

      {error_msg, code} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: error_msg, code: code}}
    end
  end
end
