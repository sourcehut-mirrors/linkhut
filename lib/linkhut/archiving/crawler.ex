defmodule Linkhut.Archiving.Crawler do
  @moduledoc """
  Defines the general behaviour for a crawler.

  Actual crawlers must also implement one of the `Direct` or `External`
  behaviours.
  """

  @typedoc "Identifies the crawler and its tool and version."
  @type crawler_meta :: %{
          tool_name: String.t(),
          tool_version: String.t() | nil,
          version: String.t()
        }

  @typedoc "Archive format a crawler produces, e.g. `webpage` or `reference`."
  @type format :: Linkhut.Archiving.MIME.archive_format()

  @typedoc """
  Why a crawler won't fetch the provided URL.
  """
  @type reject_reason :: %{required(:reason) => atom(), optional(atom()) => term()}

  @type acceptance :: {:ok, format()} | {:reject, reject_reason()}

  @callback source_type() :: String.t()
  @callback meta() :: crawler_meta()
  @callback queue() :: atom()

  @doc "The crawler module's version."
  @callback module_version() :: String.t()

  @doc "The URL schemes and hosts the crawler handles."
  @callback applies_to() :: [
              schemes: [String.t()],
              hosts: :any | [String.t()],
              except_hosts: [String.t()]
            ]

  @optional_callbacks [applies_to: 0]

  @doc """
  Fetches `url`. The options:

    - `:staging_dir`: directory where the crawler will temporarily download
      resources to
    - `:format`: the archive format the crawler accepted the URL with
    - `:bookmarked_at`: timestamp of when the link was bookmarked
    - `:log`: the archiving log handle to use for logging events
  """
  @callback fetch(url :: String.t(), opts :: keyword()) ::
              {:ok, {:file, map()}}
              | {:ok, {:external, map()}}
              | {:ok, :not_available}
              | {:error, map()}
              | {:error, map(), :noretry}

  defmodule External do
    @moduledoc """
    Crawler that relies on an external service to provide the snapshot for the
    bookmarked URL.
    """

    @callback accepts(url :: String.t()) :: Linkhut.Archiving.Crawler.acceptance()

    @doc "Rate limit for the external service."
    @callback rate_limit() :: {scale_ms :: pos_integer(), limit :: pos_integer()}

    @optional_callbacks [rate_limit: 0]
  end

  defmodule Direct do
    @moduledoc "Crawler that fetches the bookmarked URL to generate a snapshot."

    @callback accepts(url :: String.t(), Linkhut.Archiving.PreflightMeta.t()) ::
                Linkhut.Archiving.Crawler.acceptance()
  end

  @default_applies_to [schemes: ["http", "https"], hosts: :any, except_hosts: []]

  @doc "Returns which URLs the crawler applies to."
  @spec applies_to(module()) :: keyword()
  def applies_to(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :applies_to, 0),
      do: Keyword.merge(@default_applies_to, module.applies_to()),
      else: @default_applies_to
  end

  @doc "Returns true if the given crawler relies on an external service."
  @spec external?(module()) :: boolean()
  def external?(module) do
    External in (module.module_info(:attributes)
                 |> Keyword.get_values(:behaviour)
                 |> List.flatten())
  end

  @base_user_agent "LinkhutArchiver/1.0 (web page snapshot for personal archiving)"

  @doc "Returns the User-Agent for crawler requests."
  def user_agent do
    case Linkhut.Config.archiving(:user_agent_suffix) do
      suffix when is_binary(suffix) and suffix != "" ->
        "LinkhutArchiver/1.0 (web page snapshot for personal archiving; #{suffix})"

      _ ->
        @base_user_agent
    end
  end
end
