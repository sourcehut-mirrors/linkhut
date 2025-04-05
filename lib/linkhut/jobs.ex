defmodule Linkhut.Jobs do
  alias Linkhut.Accounts.User
  alias Linkhut.Jobs.Import
  alias Linkhut.Repo

  def create_import(%User{} = user, job, overrides, attrs \\ %{}) do
    %Import{user_id: user.id, job_id: job.id, overrides: overrides}
    |> Import.changeset(attrs)
    |> Repo.insert()
  end

  def get_import(user_id, job_id) do
    Import
    |> Repo.get_by(user_id: user_id, job_id: job_id)
  end

  def update_import(%Import{} = import, attrs) do
    import
    |> Import.changeset(attrs)
    |> Repo.update()
  end
end
