defmodule Linkhut.Repo.Migrations.DropSnapshotsFormatSourceCheck do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE snapshots DROP CONSTRAINT snapshots_format_source_check"
  end

  def down do
    execute """
    ALTER TABLE snapshots ADD CONSTRAINT snapshots_format_source_check CHECK (
      (source = 'singlefile' AND format = 'webpage') OR
      (source = 'httpfetch'  AND format IN ('webpage', 'pdf', 'text')) OR
      (source = 'wayback'    AND format = 'reference') OR
      (source = 'upload'     AND format IN ('webpage', 'pdf', 'text'))
    )
    """
  end
end
