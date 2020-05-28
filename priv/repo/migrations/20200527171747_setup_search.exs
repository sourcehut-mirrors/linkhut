defmodule Linkhut.Repo.Migrations.SetupSearch do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :search_vector, :tsvector
    end

    execute "CREATE INDEX link_search_index ON links USING GIN(search_vector)",
            "DROP INDEX link_search_index"

    execute """
            CREATE FUNCTION link_search_trigger() RETURNS trigger AS $$
            BEGIN
            NEW.search_vector :=
              setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.title,'')), 'A') ||
              setweight(to_tsvector(NEW.language::regconfig, coalesce(NEW.notes,'')), 'B') ||
              setweight(array_to_tsvector(coalesce(NEW.tags,'{}')::text[]), 'D');
            return NEW;
            END
            $$ LANGUAGE plpgsql
            """,
            "DROP FUNCTION link_search_trigger()"

    execute """
            CREATE TRIGGER link_search_update
            BEFORE INSERT OR UPDATE OF title, notes, language ON links
            FOR EACH ROW EXECUTE PROCEDURE link_search_trigger()
            """,
            "DROP TRIGGER link_search_update ON links"

    ## Force trigger to execute on all rows
    execute "UPDATE links SET language = language", ""
  end
end
