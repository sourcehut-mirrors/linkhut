defmodule Linkhut.Repo.Migrations.AddRolesToUsers do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:users) do
      add :roles, {:array, :string}, default: []
    end

    if direction() == :up do
      flush()

      execute(&execute_up/0)
    end
  end

  defp execute_up do
    from(l in Linkhut.Accounts.User,
      update: [set: [type: :unconfirmed]]
    )
    |> Linkhut.Repo.update_all([])
  end
end
