defmodule Linkhut.Links do
  @moduledoc """
  The Links context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Links.PublicLink
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
    |> maybe_refresh_views()
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
    |> maybe_refresh_views()
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
    |> maybe_refresh_views()
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
  @spec get(String.t(), integer()) :: link() | nil
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
    Enum.reduce(params, dynamic(true), &filter/2)
  end

  defp filter({:user_id, id}, dynamic) do
    dynamic([l], ^dynamic and l.user_id == ^id)
  end

  defp filter({:visible_as, :public}, dynamic) do
    dynamic([l], ^dynamic and not (l.is_private or l.is_unread))
  end

  defp filter({:visible_as, id}, dynamic) when is_number(id) do
    dynamic([l], ^dynamic and (l.user_id == ^id or not (l.is_private or l.is_unread)))
  end

  defp filter({:url, url}, dynamic) do
    dynamic([l], ^dynamic and l.url == ^url)
  end

  defp filter({:is_private, is_private}, dynamic) do
    dynamic([l], ^dynamic and l.is_private == ^is_private)
  end

  defp filter({:is_unread, is_unread}, dynamic) do
    dynamic([l], ^dynamic and l.is_unread == ^is_unread)
  end

  defp filter({:dt, date}, dynamic) do
    dynamic([l], ^dynamic and fragment("?::date", l.inserted_at) == ^date)
  end

  defp filter({:from, datetime}, dynamic) when not is_nil(datetime) do
    dynamic([l], ^dynamic and l.inserted_at >= ^datetime)
  end

  defp filter({:to, datetime}, dynamic) when not is_nil(datetime) do
    dynamic([l], ^dynamic and l.inserted_at <= ^datetime)
  end

  defp filter({:query, query}, dynamic) when is_binary(query) and query != "" do
    dynamic([l], ^dynamic and fragment("? @@ websearch_to_tsquery(?)", l.search_vector, ^query))
  end

  defp filter({:tags, tags}, dynamic) when not is_nil(tags) and tags != [] do
    dynamic(
      [l],
      ^dynamic and
        fragment(
          "array_lowercase(?) @> string_to_array(?, ',')::varchar[]",
          l.tags,
          ^Enum.map_join(tags, ",", &String.downcase/1)
        )
    )
  end

  defp filter({:hashes, hashes}, dynamic) when not is_nil(hashes) and hashes != [] do
    dynamic([l], ^dynamic and fragment("md5(?)", l.url) in ^hashes)
  end

  defp filter({_, _}, dynamic), do: dynamic

  @doc """
  Returns all non-private links
  """
  def all() do
    links()
    |> where(is_private: false)
    |> order_by(desc: :inserted_at)
  end

  @doc """
  Returns the most recent link modified (as in inserted or updated) by a user
  """
  def most_recent(%User{} = user) do
    links()
    |> where(user_id: ^user.id)
    |> order_by([l], desc: fragment("greatest(?, ?)", l.inserted_at, l.updated_at))
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns most recent public links
  """
  def recent(params, days \\ 30) do
    datetime = DateTime.add(DateTime.now!("Etc/UTC"), -days, :day)

    links()
    |> where([_, _, u], u.is_banned == false)
    |> where(is_private: false)
    |> where(is_unread: false)
    |> where([_, s], s.user_daily_entry <= 2)
    |> where([_, s], s.rank == 0.0)
    |> where([l], l.inserted_at >= ^datetime)
    |> where([l], fragment("NOT 'via:ifttt' = ANY(?)", l.tags))
    |> where([_, _, u], u.type != ^:unconfirmed)
    |> ordering(params)
  end

  @doc """
  Returns the most popular public links
  """
  def popular(params, popularity \\ 3) do
    links()
    |> where([_, _, u], u.is_banned == false)
    |> where([l, s, _], s.rank == 1.0)
    |> where(is_private: false)
    |> where(is_unread: false)
    |> where([_, s, _], s.saves >= ^popularity)
    |> where([l], fragment("NOT 'via:ifttt' = ANY(?)", l.tags))
    |> where([_, _, u], u.type != ^:unconfirmed)
    |> ordering(params)
  end

  @doc """
  Returns the number of unread links for a user
  """
  def unread_count(user_id) do
    Link
    |> where(user_id: ^user_id)
    |> where(is_unread: true)
    |> exclude(:preload)
    |> Repo.aggregate(:count)
  end

  def links(params \\ []) do
    from(l in Link,
      left_join: s in PublicLink,
      on: [id: l.id],
      left_join: u in assoc(l, :user),
      select_merge: ^select_fields(params),
      preload: [:user, :variants, :savers]
    )
    |> where(^filter_where(params))
  end

  defp select_fields(params) do
    Enum.reduce(
      params,
      %{
        saves: dynamic([_, s], coalesce(s.saves, 1))
      },
      &select_field/2
    )
  end

  defp select_field({:query, query}, fields) when is_binary(query) and query != "" do
    Map.merge(fields, %{
      score:
        dynamic(
          [l],
          fragment("ts_rank(search_vector, websearch_to_tsquery(?))", ^query)
          |> selected_as(:score)
        )
    })
  end

  defp select_field({_, _}, fields), do: fields

  def ordering(query, opts) do
    sort_column = Keyword.get(opts, :sort_by, :recency)
    sort_direction = Keyword.get(opts, :order, :desc)

    column =
      case sort_column do
        :recency -> dynamic([l], field(l, :inserted_at))
        :popularity -> dynamic([_, s], field(s, :saves))
        :relevancy -> dynamic([_], selected_as(:score))
      end

    filter_order_by =
      case sort_direction do
        :asc -> [asc: column, asc: :inserted_at]
        :desc -> [desc: column, desc: :inserted_at]
      end

    query |> order_by(^filter_order_by)
  end

  defp maybe_refresh_views({:ok, %Link{is_private: false}} = result) do
    Linkhut.Workers.RefreshViewsWorker.new(%{}) |> Oban.insert!()
    result
  end

  defp maybe_refresh_views(result), do: result
end
