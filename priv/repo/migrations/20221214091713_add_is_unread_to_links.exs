defmodule Linkhut.Repo.Migrations.AddIsUnreadToLinks do
  use Ecto.Migration
  import Ecto.Query

  def change do
    alter table(:links) do
      add :is_unread, :boolean, default: false, null: false
    end

    create index(:links, [:is_unread])

    if (direction() == :up) do
      flush()

      execute(&execute_up/0)
    end
  end


  defp execute_up, do: from(l in Linkhut.Links.Link, where: fragment("lower(tags::text)::text[] && ARRAY['unread','toread']"), update: [set: [is_unread: true]]) |> Linkhut.Repo.update_all([])

end
