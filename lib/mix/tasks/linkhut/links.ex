defmodule Mix.Tasks.Linkhut.Links do
  use Mix.Task

  import Ecto.Query
  import Mix.Linkhut

  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @moduledoc """
  Link maintenance tasks.

  ## Usage

      mix linkhut.links recompute_normalized_urls [--dry-run] [--batch-size N]

  Recomputes `normalized_url` for all links using the current normalization
  pipeline. Useful after changes to URL normalization rules.
  """

  @shortdoc "Link maintenance tasks"

  @default_batch_size 1000

  def run(["recompute_normalized_urls" | args]) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [dry_run: :boolean, batch_size: :integer])

    start_linkhut()
    recompute_normalized_urls(opts)
  end

  def run(_) do
    shell_error("""
    Usage:
      mix linkhut.links recompute_normalized_urls [--dry-run] [--batch-size N]
    """)
  end

  defp recompute_normalized_urls(opts) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    if dry_run?, do: shell_info("=== DRY RUN ===\n")

    total = Repo.aggregate(Link, :count)
    {scanned, updated} = recompute_loop(0, batch_size, dry_run?, 0, 0)

    shell_info("\nDone. Scanned: #{scanned}/#{total}, Updated: #{updated}")
  end

  defp recompute_loop(last_id, batch_size, dry_run?, scanned, updated) do
    links =
      from(l in Link,
        where: l.id > ^last_id,
        order_by: [asc: l.id],
        limit: ^batch_size,
        select: {l.id, l.url, l.normalized_url}
      )
      |> Repo.all()

    if links == [] do
      {scanned, updated}
    else
      batch_updated = Enum.count(links, &maybe_update_link(&1, dry_run?))

      new_last_id = links |> List.last() |> elem(0)

      recompute_loop(
        new_last_id,
        batch_size,
        dry_run?,
        scanned + length(links),
        updated + batch_updated
      )
    end
  end

  defp maybe_update_link({id, url, current_normalized}, dry_run?) do
    expected = Linkhut.Links.Url.normalize(url)

    if expected != current_normalized do
      shell_info("  ##{id}: #{current_normalized} -> #{expected}")

      unless dry_run? do
        from(l in Link, where: l.id == ^id)
        |> Repo.update_all(set: [normalized_url: expected])
      end

      true
    else
      false
    end
  end
end
