defmodule Linkhut.Repo.Migrations.ChangeSnapshotsLinkOnDelete do
  use Ecto.Migration

  def change do
    execute(
      "ALTER TABLE snapshots DROP CONSTRAINT snapshots_link_id_fkey,
       ADD CONSTRAINT snapshots_link_id_fkey
         FOREIGN KEY (link_id) REFERENCES links(id) ON DELETE SET NULL",
      "ALTER TABLE snapshots DROP CONSTRAINT snapshots_link_id_fkey,
       ADD CONSTRAINT snapshots_link_id_fkey
         FOREIGN KEY (link_id) REFERENCES links(id) ON DELETE CASCADE"
    )
  end
end
