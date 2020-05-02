defmodule Linkhut.Repo do
  use Ecto.Repo,
    otp_app: :linkhut,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  alias Linkhut.Model.{Link, User}
  alias Linkhut.Pagination
  alias Linkhut.Repo

  # links

  def links(username) when is_binary(username) do
    user = Repo.get_by(User, username: username)
    if user != nil, do: links(user_id: user.id), else: []
  end

  def links(query) do
    query_links(query)
    |> Repo.all()
    |> Repo.preload(:user)
  end

  def links(query, page: page) do
    query_links(query)
    |> Pagination.page(page, per_page: 20)
    |> Map.update!(:entries, &Repo.preload(&1, :user))
  end

  def links_by_date(query, page: page) do
    links(query, page: page)
    |> Map.update!(
      :entries,
      &Enum.chunk_by(&1, fn link -> DateTime.to_date(link.inserted_at) end)
    )
  end

  def link(url, user_id) do
    Repo.get_by(Link, url: url, user_id: user_id)
  end

  defp query_links(where) do
    from l in Link,
      where: ^where
  end

  # tags

  def tags(query) do
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
