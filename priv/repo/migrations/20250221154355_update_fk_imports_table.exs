defmodule Linkhut.Repo.Migrations.UpdateFkImportsTable do
  use Ecto.Migration

  def up do
    drop constraint(:imports, "imports_user_id_fkey")
    drop constraint(:imports, "imports_job_id_fkey")

    alter table(:imports) do
      modify :user_id, references(:users, on_delete: :delete_all)
      modify :job_id, references(:oban_jobs, on_delete: :delete_all)
    end
  end

  def down do
    drop constraint(:imports, "imports_user_id_fkey")
    drop constraint(:imports, "imports_job_id_fkey")

    alter table(:imports) do
      modify :user_id, references(:users, on_delete: :nothing)
      modify :job_id, references(:oban_jobs, on_delete: :nothing)
    end
  end
end
