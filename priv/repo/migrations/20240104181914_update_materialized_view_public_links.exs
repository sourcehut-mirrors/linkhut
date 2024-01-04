defmodule Linkhut.Repo.Migrations.UpdateMaterializedViewPublicLinks do
  use Ecto.Migration

  def change do
    execute "ALTER MATERIALIZED VIEW public_links RENAME TO public_links_old;",
            "ALTER MATERIALIZED VIEW IF EXISTS public_links_old TO public_links;"

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
            """,
            "DROP MATERIALIZED VIEW IF EXISTS public_links;"
  end
end
