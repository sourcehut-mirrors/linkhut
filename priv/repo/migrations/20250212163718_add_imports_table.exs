defmodule Linkhut.Repo.Migrations.AddImportsTable do
  use Ecto.Migration

  def change do
    create table(:imports) do
      add :user_id, references(:users, on_delete: :nothing)
      add :job_id, references(:oban_jobs, on_delete: :nothing)
      add :state, :string, default: "in_progress", null: false
      add :total, :integer
      add :saved, :integer
      add :failed, :integer
      add :failed_records, :map

      timestamps()
    end
  end
end
