defmodule Linkhut.Repo.Migrations.AddInsertedAtToPublicLinks do
  use Ecto.Migration

  def up do
    execute "DROP MATERIALIZED VIEW IF EXISTS public_links;"

    execute """
    CREATE MATERIALIZED VIEW public_links AS
        SELECT
               l.id,
               l.url,
               l.user_id,
               l.inserted_at,
               percent_rank() OVER "reverse_order" AS "rank",
               rank() OVER "daily_entry" AS "user_daily_entry",
               count(l.url) OVER "distinct_link" AS "saves",
               u.username AS "username"
        FROM links l
        JOIN users u on l.user_id = u.id
        WHERE (NOT l.is_private AND NOT l.is_unread AND NOT u.unlisted)
        WINDOW
          "distinct_link" AS (PARTITION BY l.url),
          "reverse_order" AS (PARTITION BY l.url ORDER BY l.inserted_at DESC),
          "daily_entry" AS (PARTITION BY date_trunc('day', l.inserted_at), l.user_id ORDER BY l.inserted_at ASC)
    """
  end

  def down do
    execute "DROP MATERIALIZED VIEW IF EXISTS public_links;"

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
end
