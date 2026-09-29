defmodule Linkhut.Archiving.LinkArchival do
  @moduledoc "Record of a link and its snapshot along with the crawler and its version."

  use Ecto.Schema

  import Ecto.Query, only: [dynamic: 1, dynamic: 2, from: 2]

  alias Linkhut.Archiving.{Crawler, CrawlRun, Snapshot}
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @type t :: Ecto.Schema.t()

  schema "link_archivals" do
    field :link_id, :id
    field :source, :string
    field :version, :string

    belongs_to :crawl_run, CrawlRun
    belongs_to :snapshot, Snapshot

    timestamps(type: :utc_datetime)
  end

  @doc """
  Dynamic query expression that determines whether `crawler` applies to the
  link bound as `:link`.
  """
  @spec applies(module()) :: Ecto.Query.dynamic_expr()
  def applies(crawler) do
    applies_to = Crawler.applies_to(crawler)
    schemes = downcase(applies_to[:schemes])

    dynamic([link: l], fragment("lower(?->>'scheme') = ANY(?)", l.metadata, ^schemes))
    |> with_hosts(applies_to[:hosts])
    |> without_hosts(applies_to[:except_hosts])
  end

  defp with_hosts(applies, :any), do: applies

  defp with_hosts(applies, hosts) do
    hosts = downcase(hosts)
    dynamic([link: l], ^applies and fragment("lower(?->>'host') = ANY(?)", l.metadata, ^hosts))
  end

  defp without_hosts(applies, []), do: applies

  defp without_hosts(applies, hosts) do
    hosts = downcase(hosts)

    dynamic(
      [link: l],
      ^applies and
        fragment("coalesce(NOT (lower(?->>'host') = ANY(?)), true)", l.metadata, ^hosts)
    )
  end

  defp downcase(values), do: Enum.map(values, &String.downcase/1)

  defp archived(crawler) do
    source = crawler.source_type()
    version = crawler.module_version()

    dynamic(
      exists(
        from a in __MODULE__,
          where:
            a.link_id == parent_as(:link).id and a.source == ^source and a.version == ^version
      )
    )
  end

  @doc """
  Dynamic query expression that determines whether any crawler in `crawlers`
  apply to the link bound as `:link`.
  """
  @spec due([module()]) :: Ecto.Query.dynamic_expr()
  def due(crawlers) do
    Enum.reduce(crawlers, dynamic(false), fn crawler, due ->
      dynamic(^due or (^applies(crawler) and not (^archived(crawler))))
    end)
  end

  @doc "Returns the configured crawlers that apply to `link`."
  @spec applicable_crawlers(Link.t()) :: [module()]
  def applicable_crawlers(link), do: crawlers_where(link, &applies/1)

  @doc """
  Returns the configured crawlers that apply to `link` and haven't archived it
  at their current version.
  """
  @spec due_crawlers(Link.t()) :: [module()]
  def due_crawlers(link), do: crawlers_where(link, &due([&1]))

  defp crawlers_where(%Link{id: link_id}, condition) do
    case Linkhut.Config.archiving(:crawlers, []) do
      [] ->
        []

      crawlers ->
        conditions = Map.new(crawlers, &{&1.source_type(), condition.(&1)})

        case Repo.one(from(l in Link, as: :link, where: l.id == ^link_id, select: ^conditions)) do
          nil -> []
          met -> Enum.filter(crawlers, &met[&1.source_type()])
        end
    end
  end
end
