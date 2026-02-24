defmodule Linkhut.Repo.Migrations.AddSnapshotsLinkStateInsertedIndex do
  use Ecto.Migration

  def change do
    create index(:snapshots, [:link_id, :state, "inserted_at DESC"],
             name: :snapshots_link_id_state_inserted_at_index
           )
  end
end
