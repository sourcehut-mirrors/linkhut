defmodule Mix.Tasks.SingleFile.Install do
  @moduledoc """
  Installs single-file-cli under `priv/bin`.

  ```bash
  $ mix singlefile.install
  $ mix singlefile.install --if-missing
  ```

  By default, it installs `SingleFile.latest_version()` but you
  can configure it in your config files, such as:

      config :single_file, :version, "#{SingleFile.latest_version()}"

  ## Options

    * `--runtime-config` - load the runtime configuration
        before executing command

    * `--if-missing` - install only if the given version
        does not exist

  """

  @shortdoc "Installs single-file under priv/bin"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    valid_options = [runtime_config: :boolean, if_missing: :boolean]

    case OptionParser.parse_head!(args, strict: valid_options) do
      {opts, []} ->
        if opts[:runtime_config], do: Mix.Task.run("app.config")

        if opts[:if_missing] && latest_version?() do
          :ok
        else
          if function_exported?(Mix, :ensure_application!, 1) do
            Mix.ensure_application!(:inets)
            Mix.ensure_application!(:ssl)
          end

          SingleFile.install()
        end

      {_, _} ->
        Mix.raise("""
        Invalid arguments to singlefile.install, expected one of:

            mix singlefile.install
            mix singlefile.install --runtime-config
            mix singlefile.install --if-missing
        """)
    end
  end

  defp latest_version?() do
    version = SingleFile.configured_version()
    match?({:ok, ^version}, SingleFile.bin_version())
  end
end
