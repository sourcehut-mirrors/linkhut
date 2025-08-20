defmodule Mix.Linkhut do
  @apps [
    :ecto,
    :ecto_sql,
    :postgrex,
    :db_connection,
    :swoosh,
    :timex,
    :oban
  ]

  @doc "Common functions to be reused in mix tasks"
  def start_linkhut do
    Application.put_env(:phoenix, :serve_endpoints, false, persistent: true)

    if !System.get_env("DEBUG") do
      try do
        Logger.remove_backend(:console)
      catch
        :exit, _ -> :ok
      end
    end

    Enum.each(@apps, &Application.ensure_all_started/1)

    children =
      [
        Linkhut.Repo,
        LinkhutWeb.Endpoint
      ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Linkhut.Supervisor
    )
  end

  def shell_prompt(prompt, defval \\ nil, defname \\ nil) do
    prompt_message = "#{prompt} [#{defname || defval}] "

    input =
      if mix_shell?(),
        do: Mix.shell().prompt(prompt_message),
        else: :io.get_line(prompt_message)

    case input do
      "\n" ->
        case defval do
          nil ->
            shell_prompt(prompt, defval, defname)

          defval ->
            defval
        end

      input ->
        String.trim(input)
    end
  end

  def shell_info(message) do
    if mix_shell?(),
      do: Mix.shell().info(message),
      else: IO.puts(message)
  end

  def shell_error(message) do
    if mix_shell?(),
      do: Mix.shell().error(message),
      else: IO.puts(:stderr, message)
  end

  @doc "Performs a safe check whether `Mix.shell/0` is available (does not raise if Mix is not loaded)"
  def mix_shell?, do: :erlang.function_exported(Mix, :shell, 0)
end
