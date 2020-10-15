defmodule Linkhut.Repo.Migrations.UpdateLinkTable do
  use Ecto.Migration

  def change do
    alter table("links") do
      modify :url, :text
      modify :title, :text
    end
  end
end
