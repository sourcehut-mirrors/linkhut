defmodule Linkhut.Links do
  @moduledoc """
  The Links context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Pagination
  alias Linkhut.Repo
  alias Linkhut.Search.Query

  @typedoc """
  A `Link` struct.
  """
  @type link :: %Link{}

  @doc """
  Creates a link.

  ## Examples

      iex> create_link(user, %{field: value})
      {:ok, %Link{}}

      iex> create_link(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_link(%User{} = user, attrs \\ %{}) do
    %Link{user_id: user.id}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a link.

  ## Examples

      iex> update_link(link, %{field: new_value})
      {:ok, %Link{}}

      iex> update_link(link, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_link(%Link{} = link, attrs) do
    link
    |> Link.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a link.

  ## Examples

      iex> delete_link(link)
      {:ok, %Link{}}

      iex> delete_link(link)
      {:error, %Ecto.Changeset{}}

  """
  def delete_link(%Link{} = link) do
    Repo.delete(link)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking link changes.

  ## Examples

      iex> change_link(link)
      %Ecto.Changeset{data: %Link{}}

  """
  def change_link(%Link{} = link, attrs \\ %{}) do
    Link.changeset(link, attrs)
  end

  def get_page(query, page: page) do
    query_links(query)
    |> Pagination.page(page, per_page: 20)
    |> Map.update!(:entries, &Repo.preload(&1, :user))
  end

  def get(url, user_id) do
    Repo.get_by(Link, url: url, user_id: user_id)
  end

  @doc """
  Finds links that match the given query.
  """
  def get_page_by_date(query, page: page) do
    get_page(query, page: page)
    |> Pagination.chunk_by(fn link -> DateTime.to_date(link.inserted_at) end)
  end

  @spec query_links(Query.t()) :: Elixir.Ecto.Query.t()
  defp query_links(search_query) do
    matched =
      Link
      |> select([:url, :user_id])
      |> intersect_all(^match_quotes(search_query.quotes))
      |> intersect_all(^match_tags(search_query.tags))
      |> intersect_all(^match_users(search_query.users))
      |> intersect_all(^match_words(search_query.words))

    Link
    |> join(:inner, [l], m in subquery(matched), on: l.url == m.url and l.user_id == m.user_id)
  end

  defp match_all() do
    Link
    |> select([:url, :user_id])
    |> where(is_private: false)
  end

  defp match_quotes(quotes) when is_nil(quotes) or length(quotes) == 0, do: match_all()

  defp match_quotes(quotes) do
    Enum.reduce(quotes, match_all(), fn quote, query ->
      query
      |> where(
        [l],
        fragment("to_tsvector(?) @@ phraseto_tsquery(?)", l.title, ^quote) or
          fragment("to_tsvector(?) @@ phraseto_tsquery(?)", l.notes, ^quote)
      )
    end)
  end

  defp match_tags(tags) when is_nil(tags) or length(tags) == 0, do: match_all()

  defp match_tags(tags) do
    match_all()
    |> where([l], fragment("? @> ARRAY[?]::varchar[]", l.tags, ^Enum.join(tags, ",")))
  end

  defp match_users(users) when is_nil(users) or length(users) == 0, do: match_all()

  defp match_users(users) do
    match_all()
    |> join(:inner, [l], u in User, on: [id: l.user_id])
    |> where([_, u], u.username in ^users)
  end

  defp match_words(words) when is_nil(words) or length(words) == 0, do: match_all()

  defp match_words(words) do
    match_all()
    |> where(
      [l],
      fragment("to_tsvector(?) @@ to_tsquery(?)", l.title, ^Enum.join(words, " | ")) or
        fragment("to_tsvector(?) @@ to_tsquery(?)", l.notes, ^Enum.join(words, " & "))
    )
  end

  # tags

  def get_tags(query) do
    query_tags(query)
    |> Repo.all()
  end

  defp query_tags(where) do
    from l in Link,
      where: ^where,
      select: [fragment("unnest(?) as tag", l.tags), count("*")],
      group_by: fragment("tag"),
      order_by: [desc: count("*"), asc: fragment("tag")]
  end
end
