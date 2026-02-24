defmodule Linkhut.Archiving.Crawler.SingleFile do
  @moduledoc "Crawler that uses the SingleFile CLI to capture a full page as a single HTML file."

  @behaviour Linkhut.Archiving.Crawler

  alias Linkhut.Archiving.Crawler.Context

  @impl true
  def type, do: "singlefile"

  @impl true
  def can_handle?(_url, %{content_type: "text/html"}) do
    true
  end

  def can_handle?(_url, _preflight_meta), do: false

  @impl true
  def fetch(%Context{link_id: link_id, url: url}) do
    staging_dir =
      Path.join(System.tmp_dir!(), "linkhut_crawl_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(staging_dir)

    args = [
      url,
      "--filename-template",
      "#{link_id}",
      "--output-directory",
      staging_dir
    ]

    case SingleFile.run(:default, args) do
      {output, code} when code == 0 ->
        {:ok,
         %{
           path: Path.join(staging_dir, "#{link_id}"),
           id: link_id,
           code: code,
           cmd: "single-file",
           args: args,
           version: SingleFile.configured_version(),
           output: IO.iodata_to_binary(output)
         }}

      {error_msg, code} ->
        File.rm_rf(staging_dir)
        {:error, %{msg: error_msg, code: code}}
    end
  end
end
