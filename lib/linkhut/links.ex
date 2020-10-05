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
    Link
    |> Repo.get_by(url: url, user_id: user_id)
  end

  @doc """
  Returns all Links belonging to the given user.
  """
  def all(%User{} = user) do
    Repo.all(from l in Link, where: l.user_id == ^user.id, order_by: [desc: l.inserted_at])
  end

  @doc """
  Returns all non-private links
  """
  def all() do
    from l in Link,
      where: not l.is_private,
      order_by: [desc: l.inserted_at]
  end

  # tags

  @doc """
  Returns a set of tags associated with a given link query
  """
  def get_tags(query) do
    query_tags(query |> exclude(:preload))
    |> Repo.all()
  end

  defp query_tags(query) do
    from l in subquery(query),
      select: [fragment("unnest(?) as tag", l.tags), count("*")],
      group_by: fragment("tag"),
      order_by: [desc: count("*"), asc: fragment("tag")]
  end
end
