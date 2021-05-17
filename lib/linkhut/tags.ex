defmodule Linkhut.Tags do
  @moduledoc """
  The Tags context.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @typedoc """
  A `Tag` struct.
  """
  @type tag :: %{count: number(), tag: String.t()}

  @spec all(User.t(), [term()]) :: list(tag())
  def all(%User{} = user, params \\ []) do
    tags = Keyword.get(params, :tags)

    query_tags(Link |> where([l], l.user_id == ^user.id))
    |> (&if(tags, do: where(&1, [t], fragment("lower(?)", t.tag) in ^tags), else: &1)).()
    |> Repo.all()
  end

  @doc """
  Returns a set of tags associated with a given link query
  """
  def for_query(query, limit: limit) do
    query_tags(query |> exclude(:preload) |> exclude(:select))
    |> limit(^limit)
    |> Repo.all()
  end

  def for_links(links) when is_list(links) do
    urls = Enum.map(links, fn %{url: url} -> url end)

    query_tags(Link |> where([l], l.url in ^urls))
    |> Repo.all()
  end

  def delete(%User{} = user, tag) do
    Link
    |> where([l], l.user_id == ^user.id)
    |> update(pull: [tags: type(^tag, :string)])
    |> Repo.update_all([])
  end

  def rename(%User{} = user, params) do
    old = Keyword.get(params, :old)
    new = Keyword.get(params, :new)

    Link
    |> where([l], l.user_id == ^user.id)
    |> update(set: [tags: fragment("array_replace(tags, ?, ?)", ^old, ^new)])
    |> Repo.update_all([])
  end

  defp query_tags(query) do
    from t in subquery(select(query, [l], %{tag: fragment("unnest(?)", l.tags)})),
      select: %{
        tag: fragment("mode() within group (order by ?) as label", t.tag),
        count: count("*")
      },
      group_by: fragment("lower(?)", t.tag),
      order_by: [desc: count("*"), asc: fragment("label")]
  end
end
