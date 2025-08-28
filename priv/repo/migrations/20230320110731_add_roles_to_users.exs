defmodule Linkhut.Repo.Migrations.AddRolesToUsers do
  use Ecto.Migration
  import Ecto.Query

  defmodule Linkhut.Repo.Migrations.AddRolesToUsers.MigratingSchema do
    use Ecto.Schema

    # Copy of the schema at the time of migration
    schema "users" do
      field(:type, Ecto.Enum,
        values: [:unconfirmed, :active_free, :active_paying],
        default: :unconfirmed
      )
    end
  end

  alias Linkhut.Repo.Migrations.AddRolesToUsers.MigratingSchema

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
    from(u in MigratingSchema,
      update: [set: [type: :unconfirmed]]
    )
    |> repo().update_all([])
  end
end
