defmodule Linkhut.Search.Term do
  @typedoc """
  A search term.

  ## Types

  * `quote`: matches a word, or list of words, exactly
  * `word`: matches a single word (applies stemming)
  * `user`: matches a username exactly
  * `tag`: matches a tag exactly
  """
  @type t ::
          {:quote, String.t()}
          | {:tag, String.t()}
          | {:user, String.t()}
          | {:word, String.t()}
end
