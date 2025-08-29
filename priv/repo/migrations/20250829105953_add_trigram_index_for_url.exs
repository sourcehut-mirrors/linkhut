defmodule Linkhut.Repo.Migrations.AddTrigramIndexForUrl do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION pg_trgm;", "DROP EXTENSION pg_trgm;"

    execute "CREATE INDEX links_url_trgm_index ON links USING GIST ((url) gist_trgm_ops);",
            "DROP INDEX links_url_trgm_index;"
  end
end
