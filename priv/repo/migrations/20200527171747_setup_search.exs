defmodule Linkhut.Repo.Migrations.SetupSearch do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :search_vector, :tsvector
    end

    # index on tags column
    execute "CREATE INDEX link_tags_index on links USING GIN (tags)",
            "DROP INDEX link_tags_index"

    # index on search_vector column
    execute "CREATE INDEX link_search_index ON links USING GIN(search_vector)",
            "DROP INDEX link_search_index"

    # trigger function that updates the search_vector column:
    #  - contents of title column is given the highest weight
    #  - contents of notes column is given the second highest weight
    #  - contents of tags is given the lowest weight
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

    # a trigger that executes link_search_update function on INSERT and UPDATE for columns: title, notes, language and tags
    execute """
            CREATE TRIGGER link_search_update
            BEFORE INSERT OR UPDATE OF title, notes, language, tags ON links
            FOR EACH ROW EXECUTE PROCEDURE link_search_trigger()
            """,
            "DROP TRIGGER link_search_update ON links"

    ## force trigger to execute on all existing rows of the links table
    execute "UPDATE links SET language = language", ""
  end
end
