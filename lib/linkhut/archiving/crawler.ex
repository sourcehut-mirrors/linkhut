defmodule Linkhut.Archiving.Crawler do
  @moduledoc """
  Defines the behaviour for a crawler.
  """

  defmodule Context do
    @moduledoc "Structured context passed to crawler `fetch/1` callbacks."

    @enforce_keys [:user_id, :link_id, :url, :snapshot_id]
    defstruct [:user_id, :link_id, :url, :snapshot_id, :preflight_meta, cookies: []]

    @type t :: %__MODULE__{
            user_id: integer(),
            link_id: integer(),
            url: String.t(),
            snapshot_id: integer(),
            preflight_meta: map() | nil,
            cookies: list()
          }
  end

  @typedoc """
  Metadata returned by the preflight step. Contents vary by scheme.

  Common optional keys:
    - `:scheme` — the URL scheme (e.g. "http", "gemini", "ftp")
    - `:content_type` — MIME type, if detectable
    - `:content_length` — size in bytes, if known
    - `:final_url` — resolved URL after redirects

  HTTP/HTTPS also includes:
    - `:status` — HTTP status code
  """
  @type preflight_meta :: map()

  @typedoc """
  Static identity metadata for the crawler.

  Required keys:
    - `:tool_name` -- human-readable tool name (e.g. "SingleFile", "Req")

  Optional keys:
    - `:version` -- version string, or nil if unknown
  """
  @type crawler_meta :: %{tool_name: String.t(), version: String.t() | nil}

  @callback type() :: String.t()
  @callback meta() :: crawler_meta()
  @callback can_handle?(url :: String.t(), preflight_meta()) :: boolean()
  @callback fetch(Context.t()) :: {:ok, map()} | {:error, map()}

  @base_user_agent "LinkhutArchiver/1.0 (web page snapshot for personal archiving)"

  @doc """
  Returns the User-Agent string for crawler HTTP requests.

  Appends the configured `user_agent_suffix` (if any) inside the comment parentheses.
  """
  def user_agent do
    case Linkhut.Config.archiving(:user_agent_suffix) do
      suffix when is_binary(suffix) and suffix != "" ->
        "LinkhutArchiver/1.0 (web page snapshot for personal archiving; #{suffix})"

      _ ->
        @base_user_agent
    end
  end
end
