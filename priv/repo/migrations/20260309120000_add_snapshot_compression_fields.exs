defmodule Linkhut.Repo.Migrations.AddSnapshotCompressionFields do
  use Ecto.Migration

  def change do
    alter table(:snapshots) do
      add :encoding, :string
      add :original_file_size_bytes, :bigint
    end
  end
end
