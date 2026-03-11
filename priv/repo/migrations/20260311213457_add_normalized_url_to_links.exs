defmodule Linkhut.Repo.Migrations.AddNormalizedUrlToLinks do
  use Ecto.Migration

  import Ecto.Query

  @disable_ddl_transaction true
  @disable_migration_lock true

  @batch_size 5000

  def up do
    execute("ALTER TABLE links ADD COLUMN IF NOT EXISTS normalized_url VARCHAR")
    flush()

    backfill()

    create_if_not_exists index(:links, [:normalized_url, :user_id], concurrently: true)
  end

  def down do
    drop_if_exists index(:links, [:normalized_url, :user_id])

    execute("ALTER TABLE links DROP COLUMN IF EXISTS normalized_url")
  end

  defp backfill do
    rows =
      from(l in "links",
        where: is_nil(l.normalized_url),
        select: %{url: l.url},
        limit: @batch_size
      )
      |> repo().all()

    if rows == [] do
      :ok
    else
      # Group rows by their normalized URL so we can batch-update all rows
      # that share the same normalized value in a single UPDATE statement.
      rows
      |> Enum.group_by(fn %{url: url} -> normalize_url(url) end)
      |> Enum.each(fn {normalized, group} ->
        urls = Enum.map(group, & &1.url) |> Enum.uniq()

        from(l in "links", where: l.url in ^urls and is_nil(l.normalized_url))
        |> repo().update_all(set: [normalized_url: normalized])
      end)

      backfill()
    end
  end

  @dns_schemes ~w(http https ftp gemini gopher)

  # Duplicated from Network.normalize_url/1 — migrations must be self-contained.
  defp normalize_url(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when is_binary(host) and scheme in @dns_schemes ->
        %URI{uri | host: String.downcase(host)}
        |> URI.to_string()

      _ ->
        url
    end
  end
end
