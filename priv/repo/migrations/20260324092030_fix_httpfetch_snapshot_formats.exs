defmodule Linkhut.Repo.Migrations.FixHttpfetchSnapshotFormats do
  use Ecto.Migration

  def up do
    execute """
    UPDATE snapshots SET format = 'pdf'
    WHERE source = 'httpfetch' AND format = 'webpage'
      AND archive_metadata->>'content_type' = 'application/pdf'
    """

    execute """
    UPDATE snapshots SET format = 'text'
    WHERE source = 'httpfetch' AND format = 'webpage'
      AND archive_metadata->>'content_type' IN ('text/plain', 'text/markdown')
    """
  end

  def down do
    # Intentionally a no-op. The up migration only corrects mis-categorized snapshots.
    # Rolling back would also revert snapshots that were correctly categorized before the bug was introduced.
    :ok
  end
end
