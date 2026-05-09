defmodule Linkhut.Archiving.RateLimit do
  @moduledoc """
  Rate limiter for archiving tasks.

  Uses `Hammer` with an ETS backend to rate limit crawls based on the crawler type (e.g: wayback_machine, singlefile).
  """
  use Hammer, backend: Hammer.ETS, algorithm: :sliding_window
end
