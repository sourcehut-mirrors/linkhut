defmodule Linkhut.Repo.Migrations.RemoveSnapshotCrawlInfo do
  use Ecto.Migration

  def change do
    alter table(:snapshots) do
      remove :crawl_info, :map, default: %{}
    end
  end
end
