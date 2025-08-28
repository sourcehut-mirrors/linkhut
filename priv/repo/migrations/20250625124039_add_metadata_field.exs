defmodule Linkhut.Repo.Migrations.AddMetadataField do
  use Ecto.Migration
  import Ecto.Query

  defmodule Linkhut.Repo.Migrations.AddMetadataField.MigratingSchema do
    use Ecto.Schema

    # Copy of the schema at the time of migration
    schema "links" do
      field(:url, :string)

      embeds_one :metadata, LinkMetadata, on_replace: :update do
        field(:scheme, :string)
        field(:host, :string)
        field(:port, :integer)
        field(:path, :string)
        field(:query, :string)
        field(:fragment, :string)
      end
    end
  end

  alias Linkhut.Repo.Migrations.AddMetadataField.MigratingSchema

  def change do
    alter table(:links) do
      add :metadata, :map
    end

    execute "CREATE INDEX links_metadata_host_index ON links ((metadata->>'host'));",
            "DROP INDEX links_metadata_host_index;"

    if direction() == :up do
      flush()

      execute(&execute_up/0)
    end
  end

  defp execute_up do
    query =
      from(l in MigratingSchema)

    stream = repo().stream(query)

    repo().transaction(fn ->
      stream
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {link, idx}, multi ->
        Ecto.Multi.update_all(
          multi,
          {:update, idx},
          from(l in MigratingSchema,
            select: l.id,
            where: l.id == ^link.id
          ),
          set: [
            metadata:
              struct(
                MigratingSchema.LinkMetadata,
                link.url
                |> URI.parse()
                |> Map.from_struct()
                |> Map.take([:scheme, :host, :port, :path, :query, :fragment])
              )
          ]
        )
      end)
      |> repo().transaction()
    end)
  end
end
