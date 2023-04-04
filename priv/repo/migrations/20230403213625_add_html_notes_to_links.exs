defmodule Linkhut.Repo.Migrations.AddHtmlNotesToLinks do
  use Ecto.Migration
  import Ecto.Query
  alias Linkhut.Links.Link

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
      from(l in Link,
        where: not is_nil(l.notes) and l.notes != ""
      )

    stream = Linkhut.Repo.stream(query)

    Linkhut.Repo.transaction(fn ->
      stream
      |> Enum.map(fn link ->
        link
        |> Link.changeset(%{notes: link.notes}, force_changes: true)
      end)
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
        Ecto.Multi.update(multi, {:update, idx}, changeset)
      end)
      |> Linkhut.Repo.transaction()
    end)
  end
end
