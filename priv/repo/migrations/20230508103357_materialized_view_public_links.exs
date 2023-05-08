defmodule Linkhut.Repo.Migrations.MaterializedViewsPublicLinks do
  use Ecto.Migration

  def change do
    execute """
            CREATE MATERIALIZED VIEW public_links AS
                SELECT url,
                       user_id,
                       min(inserted_at) OVER "distinct_link" AS "first",
                       max(inserted_at) OVER "distinct_link" AS "last",
                       count(url) OVER "distinct_link" AS "saves"
                FROM links
                WHERE (NOT is_private AND NOT is_unread)
                WINDOW "distinct_link" AS (PARTITION BY url)
            ;
            """,
            "DROP MATERIALIZED VIEW IF EXISTS public_links;"

    execute """
            CREATE FUNCTION refresh_public_links()
              RETURNS trigger AS $$
              BEGIN
              REFRESH MATERIALIZED VIEW public_links;
              RETURN NULL;
            END;
            $$ LANGUAGE plpgsql;
            """,
            "DROP FUNCTION IF EXISTS refresh_public_links"

    execute """
            CREATE TRIGGER refresh_public_links_trigger
            AFTER INSERT OR UPDATE OR DELETE
            ON links
            FOR EACH STATEMENT
            EXECUTE PROCEDURE refresh_public_links();
            """,
            "DROP TRIGGER IF EXISTS refresh_public_links_trigger on links"
  end
end
