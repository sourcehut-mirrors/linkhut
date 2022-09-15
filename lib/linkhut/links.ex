defmodule Linkhut.Links do
  @moduledoc """
  The Links context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Repo

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
  def create_link(%User{} = user, attrs) do
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

  @doc """
  Returns a Link for a given url and user id.

  Returns `nil` if no result is found.

  ## Examples

      iex> get("http://example.com", 123)
      %Link{}

      iex> get("http://example.com", 456)
      nil
  """
  @spec get(String.t(), integer()) :: link()
  def get(url, user_id) do
    links()
    |> Repo.get_by(url: url, user_id: user_id)
  end

  @doc """
  Returns a Link for a given url and user id.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get!("http://example.com", 123)
      %Link{}

      iex> get!("http://example.com", 456)
      ** (Ecto.NoResultsError)
  """
  @spec get!(String.t(), integer()) :: link()
  def get!(url, user_id) do
    links()
    |> Repo.get_by!(url: url, user_id: user_id)
  end

  def all(params) when is_list(params) do
    count = Keyword.get(params, :count)
    start = Keyword.get(params, :start)

    links()
    |> where(^filter_where(params))
    |> order_by(desc: :inserted_at)
    |> (&if(count, do: limit(&1, ^count), else: &1)).()
    |> (&if(start, do: offset(&1, ^start), else: &1)).()
    |> Repo.all()
  end

  @doc """
  Returns all Links belonging to the given user.
  """
  def all(%User{} = user, params \\ []) do
    params = Keyword.put(params, :user_id, user.id)

    all(params)
  end

  defp filter_where(params) do
    Enum.reduce(params, dynamic(true), fn
      {:user_id, id}, dynamic ->
        dynamic([l], ^dynamic and l.user_id == ^id)

      {:url, url}, dynamic ->
        dynamic([l], ^dynamic and l.url == ^url)

      {:is_private, is_private}, dynamic ->
        dynamic([l], ^dynamic and l.is_private == ^is_private)

      {:dt, date}, dynamic ->
        dynamic([l], ^dynamic and fragment("?::date", l.inserted_at) == ^date)

      {:from, datetime}, dynamic when not is_nil(datetime) ->
        dynamic([l], ^dynamic and l.inserted_at >= ^datetime)

      {:to, datetime}, dynamic when not is_nil(datetime) ->
        dynamic([l], ^dynamic and l.inserted_at <= ^datetime)

      {:tags, tags}, dynamic when not is_nil(tags) and tags != [] ->
        dynamic(
          [l],
          ^dynamic and
            fragment(
              "array_lowercase(?) @> string_to_array(?, ',')::varchar[]",
              l.tags,
              ^Enum.map_join(tags, ",", &String.downcase/1)
            )
        )

      {:hashes, hashes}, dynamic when not is_nil(hashes) and hashes != [] ->
        dynamic([l], ^dynamic and fragment("md5(?)", l.url) in ^hashes)

      {_, _}, dynamic ->
        dynamic
    end)
  end

  @doc """
  Returns all non-private links
  """
  def all() do
    links()
    |> where(is_private: false)
    |> order_by(desc: :inserted_at)
  end

  @doc """
  Returns the most recent link inserted by a user
  """
  def most_recent(%User{} = user) do
    links()
    |> where(user_id: ^user.id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def links() do
    from(l in Link,
      left_join: s in subquery(get_shares()),
      on: [url: l.url, user_id: l.user_id],
      select_merge: %{shares: s.shares}
    )
  end

  defp get_shares() do
    from(l in Link,
      join: o in Link,
      on: [url: l.url],
      group_by: [l.url, l.user_id],
      select: %{
        url: l.url,
        user_id: l.user_id,
        shares: count(o.url) |> filter(l.user_id != o.user_id and not o.is_private)
      }
    )
  end
end
