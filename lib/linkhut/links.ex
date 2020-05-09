defmodule Linkhut.Links do
  @moduledoc """
  The Links context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Pagination
  alias Linkhut.Repo

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
  Returns the 20 most recent public links belonging to a given user.

  Returns `[]` if no results were found

  ## Examples

      iex> get_public_links("user123")
      [%Link{}]

      iex> get_public_links("not_a_user")
      []
  """
  def get_public_links(username) do
    user = Repo.get_by(User, username: username)
    if user != nil, do: get_page([user_id: user.id, is_private: false], page: 1).entries, else: []
  end

  def get_page(query, page: page) do
    query_links(query)
    |> Pagination.page(page, per_page: 1)
    |> Map.update!(:entries, &Repo.preload(&1, :user))
  end

  def get_page_by_date(query, page: page) do
    get_page(query, page: page)
    |> Map.update!(
      :entries,
      &Enum.chunk_by(&1, fn link -> DateTime.to_date(link.inserted_at) end)
    )
  end

  def get(url, user_id) do
    Repo.get_by(Link, url: url, user_id: user_id)
  end

  defp query_links(where) do
    from l in Link,
      where: ^where
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
