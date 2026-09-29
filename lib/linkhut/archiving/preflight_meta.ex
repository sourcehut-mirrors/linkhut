defmodule Linkhut.Archiving.PreflightMeta do
  @moduledoc "Structured metadata from the preflight step."

  defstruct [:scheme, :content_type, :content_length, :final_url, :status, :method]

  @type t() :: %__MODULE__{
          scheme: String.t() | nil,
          content_type: String.t() | nil,
          content_length: integer() | nil,
          final_url: String.t() | nil,
          status: integer() | nil,
          method: String.t() | nil
        }
end
