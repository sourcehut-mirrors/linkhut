defmodule Linkhut.Repo.Migrations.RenameSnapshotInProgressToPending do
  use Ecto.Migration

  def up do
    execute "UPDATE snapshots SET state = 'pending' WHERE state = 'in_progress'"
  end

  def down do
    execute "UPDATE snapshots SET state = 'in_progress' WHERE state IN ('pending', 'crawling')"
  end
end
