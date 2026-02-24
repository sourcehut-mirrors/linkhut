defmodule Linkhut.Archiving.Crawler do
  @moduledoc """
  Defines the behaviour for a crawler.
  """

  defmodule Context do
    @moduledoc "Structured context passed to crawler `fetch/1` callbacks."

    @enforce_keys [:user_id, :link_id, :url, :snapshot_id]
    defstruct [:user_id, :link_id, :url, :snapshot_id, cookies: []]

    @type t :: %__MODULE__{
            user_id: integer(),
            link_id: integer(),
            url: String.t(),
            snapshot_id: integer(),
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

  @callback type() :: String.t()
  @callback can_handle?(url :: String.t(), preflight_meta()) :: boolean()
  @callback fetch(Context.t()) :: {:ok, map()} | {:error, map()}
end
