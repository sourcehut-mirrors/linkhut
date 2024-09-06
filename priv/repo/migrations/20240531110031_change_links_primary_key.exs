defmodule Linkhut.Repo.Migrations.ChangeLinksPrimaryKey do
  use Ecto.Migration

  def up do
    execute "DROP MATERIALIZED VIEW IF EXISTS public_links_old;"
    execute "DROP MATERIALIZED VIEW IF EXISTS public_links;"

    drop constraint("links", "links_pkey")

    alter table(:links) do
      add :id, :identity, primary_key: true
    end

    drop index(:links, [:url, :user_id])
    create unique_index(:links, [:url, :user_id])

    execute """
    CREATE MATERIALIZED VIEW public_links AS
        SELECT
               l.id,
               l.url,
               l.user_id,
               min(l.inserted_at) OVER "distinct_link" AS "first",
               max(l.inserted_at) OVER "distinct_link" AS "last",
               count(l.url) OVER "distinct_link" AS "saves",
               u.username AS "username"
        FROM links l
        JOIN users u on l.user_id = u.id
        WHERE (NOT l.is_private AND NOT l.is_unread AND NOT u.unlisted)
        WINDOW "distinct_link" AS (PARTITION BY l.url)
    ;
    """
  end

  def down do
    drop constraint("links", "links_pkey")

    execute "DROP MATERIALIZED VIEW IF EXISTS public_links;"

    alter table(:links) do
      modify :url, :text, primary_key: true
      modify :user_id, :integer, primary_key: true
      remove :id
    end

    execute """
    CREATE MATERIALIZED VIEW public_links AS
        SELECT l.url,
               l.user_id,
               min(l.inserted_at) OVER "distinct_link" AS "first",
               max(l.inserted_at) OVER "distinct_link" AS "last",
               count(l.url) OVER "distinct_link" AS "saves",
               u.username AS "username"
        FROM links l
        JOIN users u on l.user_id = u.id
        WHERE (NOT l.is_private AND NOT l.is_unread AND NOT u.unlisted)
        WINDOW "distinct_link" AS (PARTITION BY l.url)
    ;
    """
  end
end
