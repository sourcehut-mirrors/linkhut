defmodule Linkhut.Repo.Migrations.DeleteRefreshPublicLinksTrigger do
  use Ecto.Migration

  def change do
    execute "DROP TRIGGER IF EXISTS refresh_public_links_trigger on links",
            """
            CREATE TRIGGER refresh_public_links_trigger
            AFTER INSERT OR UPDATE OR DELETE
            ON links
            FOR EACH STATEMENT
            EXECUTE PROCEDURE refresh_public_links();
            """

    execute "DROP FUNCTION IF EXISTS refresh_public_links",
            """
            CREATE FUNCTION refresh_public_links()
            RETURNS trigger AS $$
            BEGIN
            REFRESH MATERIALIZED VIEW public_links;
            RETURN NULL;
            END;
            $$ LANGUAGE plpgsql;
            """
  end
end
