defmodule Linkhut.Repo.Migrations.AddIsUnreadToLinks do
  use Ecto.Migration
  import Ecto.Query

  defmodule Linkhut.Repo.Migrations.AddIsUnreadToLinks.MigratingSchema do
    use Ecto.Schema

    # Copy of the schema at the time of migration
    schema "links" do
      field(:tags, {:array, :string})
      field(:is_unread, :boolean)
    end
  end

  alias Linkhut.Repo.Migrations.AddIsUnreadToLinks.MigratingSchema

  def change do
    alter table(:links) do
      add :is_unread, :boolean, default: false, null: false
    end

    create index(:links, [:is_unread])

    if direction() == :up do
      flush()

      execute(&execute_up/0)
    end
  end

  defp execute_up do
    from(l in MigratingSchema,
      where: fragment("lower(tags::text)::text[] && ARRAY['unread','toread']"),
      update: [set: [is_unread: true]]
    )
    |> repo().update_all([])
  end
end
