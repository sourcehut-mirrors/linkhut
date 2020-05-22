defmodule Linkhut.Search.Term do
  @moduledoc """
  A search term.
  """

  @typedoc """
  A search term.

  ## Types

  * `quote`: matches a word, or list of words, exactly
  * `word`: matches a single word (applies stemming)
  * `user`: matches a username exactly
  * `tag`: matches a tag exactly
  """
  @type t :: quote | tag | user | word

  @typep quote :: {:quote, String.t()}
  @typep tag :: {:tag, String.t()}
  @typep user :: {:user, String.t()}
  @typep word :: {:word, String.t()}

  @doc """
  Creates a search term given a type and a value.

  Raises if the given type is not one of the supported term types.

  ### Examples

      iex> term(:quote, "A sentence")
      {:quote, "A sentence")

      iex> term(:invalid, "")
      ** (ArgumentError) invalid term type :invalid

  """
  @spec term(atom(), String.t()) :: t
  def term(type, value) when type in [:quote, :tag, :user, :word], do: {type, value}
  def term(type, _), do: raise(ArgumentError, message: "invalid term type '#{type}'")

  @doc """
  Creates a `quote` term for a given value

  ### Examples

      iex> quote("A sentence")
      {:quote, "A sentence")

  """
  @spec quote(String.t()) :: quote()
  def quote(value \\ ""), do: term(:quote, value)

  @doc """
  Creates a `tag` term for a given value

  ### Examples

      iex> tag("a-tag")
      {:tag, "a-tag")

  """
  @spec tag(String.t()) :: tag()
  def tag(value \\ ""), do: term(:tag, value)

  @doc """
  Creates a `user` term for a given value

  ### Examples

      iex> user("username")
      {:user, "username")

  """
  @spec user(String.t()) :: user()
  def user(value \\ ""), do: term(:user, value)

  @doc """
  Creates a `word` term for a given value

  ### Examples

      iex> word("foo")
      {:word, "foo")

  """
  @spec word(String.t()) :: word()
  def word(value \\ ""), do: term(:word, value)
end
