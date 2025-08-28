defmodule Linkhut.Repo.Migrations.AddHtmlNotesToLinks do
  use Ecto.Migration
  import Ecto.Query

  defmodule Linkhut.Repo.Migrations.AddHtmlNotesToLinks.MigratingSchema do
    use Ecto.Schema

    # Copy of the schema at the time of migration
    schema "links" do
      field(:url, :string, primary_key: true)
      field(:user_id, :id, primary_key: true)

      field(:notes, :string)
      field(:html_notes, :string)
    end
  end

  alias Linkhut.Repo.Migrations.AddHtmlNotesToLinks.MigratingSchema

  def change do
    alter table(:links) do
      add :notes_html, :text, default: ""
    end

    if direction() == :up do
      flush()

      execute(&execute_up/0)
    end
  end

  defp execute_up do
    query =
      from(l in MigratingSchema,
        where: not is_nil(l.notes) and l.notes != "",
        select: [l.url, l.user_id]
      )

    stream = repo().stream(query)

    repo().transaction(fn ->
      stream
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {link, idx}, multi ->
        Ecto.Multi.update_all(
          multi,
          {:update, idx},
          from(l in MigratingSchema,
            select: [l.url, l.user_id, l.notes],
            where: l.url == ^link.url and l.user_id == ^link.user_id
          ),
          set: [
            html_notes:
              HtmlSanitizeEx.Scrubber.scrub(
                Earmark.as_html!(link.notes, pure_links: false),
                Linkhut.Html.Scrubber
              )
          ]
        )
      end)
      |> repo().transaction()
    end)
  end
end
