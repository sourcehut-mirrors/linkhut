defmodule SingleFile do
  @moduledoc """
  SingleFile is a installer and runner for [SingleFile CLI](https://github.com/gildas-lormeau/single-file-cli).

  ## Profiles

  You can define multiple configuration profiles. By default, there is a
  profile called `:default` which you can configure its args:

      config :single_file,
        version: "2.0.75",
        default: [
          args: ~w(--crawl-links=true --crawl-inner-links-only=false)
        ]

  ## SingleFile configuration

  There are several global configurations for the `single_file` application:

    * `:version` - the expected SingleFile version.

    * `:path` - the path to the SingleFile executable. By default
      it is automatically downloaded and placed inside the `priv/bin` directory
      of your current app.

  Each profile can also be configured with the following options:

    * `:args` - additional command line arguments to pass to single-file-cli

    * `:cd` - the directory to run the command in. Defaults to the current
      working directory.

    * `:env` - environment variables to set when running the command.

  Overriding the `:path` is not recommended, as we will automatically
  download and manage `singlefile` for you. But in case you can't download
  it (for example, the GitHub releases are behind a proxy), you may want to
  set the `:path` to a configurable system location.

  For instance, you can install `singlefile` globally with `npm`:

      $ npm install -g single-file-cli

  Once you find the location of the executable, you can store it in a
  `MIX_SINGLE_FILE_PATH` environment variable, which you can then read in
  your configuration file:

      config :single_file, path: System.get_env("MIX_SINGLE_FILE_PATH")

  Note that overriding `:path` disables version checking.
  """

  require Logger

  @doc false
  # Latest known version at the time of publishing.
  def latest_version, do: "2.0.75"

  @doc """
  Returns the configured SingleFile version.
  """
  def configured_version do
    Application.get_env(:single_file, :version, latest_version())
  end

  @doc """
  Returns the configuration for the given profile.

  Returns nil if the profile does not exist.
  """
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:single_file, profile) ||
      raise ArgumentError, """
      unknown single_file profile. Make sure the profile named #{inspect(profile)} is defined in your config files, such as:

          config :single_file,
            #{profile}: [
              args: ~w(--crawl-links=true --crawl-inner-links-only=false)
            ]
      """
  end

  defp dest_bin_path(platform, base_path) do
    target = target(platform)
    Path.join(base_path, "single-file-cli-#{target}")
  end

  @doc """
  Returns the path to the `single-file` executable.
  """
  def bin_path do
    cond do
      env_path = Application.get_env(:single_file, :path) ->
        List.wrap(env_path)

      Code.ensure_loaded?(Mix.Project) ->
        dest_bin_path(platform(), Path.join(Mix.Project.app_path(), "priv/bin"))

      true ->
        dest_bin_path(platform(), "priv/bin")
    end
  end

  @doc """
  Returns the version of the SingleFile executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    path = bin_path()

    with true <- path_exist?(path),
         {result, 0} <- cmd(path, ["--version"]) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  defp cmd(command_path, extra_args, opts \\ []) do
    case System.cmd(command_path, extra_args, opts) do
      {:error, reason} ->
        Logger.error("SingleFile command failed",
          command: command_path,
          args: extra_args,
          reason: reason
        )

        {:error, reason}

      {output, exit_code} ->
        {output, exit_code}
    end
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.

  ## Examples

      SingleFile.run(:default, ["--version"])

  """
  def run(profile, extra_args) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    config_args = config[:args] || []

    system_opts = [
      cd: config[:cd] || File.cwd!(),
      env: config[:env] || %{},
      stderr_to_stdout: true
    ]

    args = config_args ++ extra_args

    bin_path()
    |> cmd(args, system_opts)
  end

  @doc """
  Installs SingleFile with `configured_version/0`.
  """
  def install do
    platform = platform()
    version = configured_version()

    tmp_opts = if System.get_env("MIX_XDG"), do: %{os: :linux}, else: %{}

    tmp_dir =
      freshdir_p(:filename.basedir(:user_cache, "singlefile", tmp_opts)) ||
        freshdir_p(Path.join(System.tmp_dir!(), "singlefile")) ||
        raise "could not install single-file. Set MIX_XDG=1 and then set XDG_CACHE_HOME to the path you want to use as cache"

    name = "single-file-#{target(platform)}"

    url =
      "https://github.com/gildas-lormeau/single-file-cli/releases/download/v#{version}/#{name}"

    download = fetch_body!(url, Path.join(tmp_dir, "single-file-cli"))

    dest_path = bin_path()
    File.mkdir_p!(Path.dirname(dest_path))
    File.rm(dest_path)
    File.cp!(download, dest_path)
    File.chmod(dest_path, 0o775)
  end

  @doc false
  def platform do
    case :os.type() do
      {:unix, :darwin} -> "apple-darwin"
      {:unix, :linux} -> "linux"
      {:unix, osname} -> raise "single_file is not available for osname: #{inspect(osname)}"
      {:win32, _} -> "windows"
    end
  end

  defp path_exist?(path) do
    File.exists?(path)
  end

  defp freshdir_p(path) do
    with {:ok, _} <- File.rm_rf(path),
         :ok <- File.mkdir_p(path) do
      path
    else
      _ -> nil
    end
  end

  # Available targets: https://github.com/gildas-lormeau/single-file-cli/releases
  defp target("windows") do
    ".exe"
  end

  defp target(platform) do
    arch_str = :erlang.system_info(:system_architecture)
    [arch | _] = arch_str |> List.to_string() |> String.split("-")

    # TODO: remove "arm" when we require OTP 24
    case arch do
      "aarch64" -> "aarch64-#{platform}"
      "x86_64" -> "x86_64-#{platform}"
      _ -> raise "single_file not available for architecture: #{arch_str}"
    end
  end

  defp fetch_body!(url, path_to_file) do
    url = String.to_charlist(url)
    Logger.debug("Downloading single-file-cli from #{url}")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    if proxy = System.get_env("HTTP_PROXY") || System.get_env("http_proxy") do
      Logger.debug("Using HTTP_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:proxy, {{String.to_charlist(host), port}, []}}])
    end

    if proxy = System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      Logger.debug("Using HTTPS_PROXY: #{proxy}")
      %{host: host, port: port} = URI.parse(proxy)
      :httpc.set_options([{:https_proxy, {{String.to_charlist(host), port}, []}}])
    end

    # https://erlef.github.io/security-wg/secure_coding_and_deployment_hardening/inets
    cacertfile = cacertfile() |> String.to_charlist()

    http_options = [
      autoredirect: true,
      ssl: [
        verify: :verify_peer,
        cacertfile: cacertfile,
        depth: 2,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ],
        versions: protocol_versions()
      ]
    ]

    case :httpc.request(:get, {url, []}, http_options, stream: String.to_charlist(path_to_file)) do
      {:ok, :saved_to_file} ->
        path_to_file

      other ->
        raise "couldn't fetch #{url}: #{inspect(other)}"
    end
  end

  defp protocol_versions do
    if otp_version() < 25 do
      [:"tlsv1.2"]
    else
      [:"tlsv1.2", :"tlsv1.3"]
    end
  end

  defp otp_version do
    :erlang.system_info(:otp_release) |> List.to_integer()
  end

  defp cacertfile() do
    Application.get_env(:single_file, :cacerts_path) || CAStore.file_path()
  end
end
