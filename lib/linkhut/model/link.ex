defmodule Linkhut.Model.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    field :title, :string
    field :notes, :string
    field :tags, {:array, :string}
    field :is_private, :boolean, default: false
    field :language, :string

    timestamps()
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :user_id, :title, :notes, :tags, :is_private, :language])
    |> validate_required([:url, :user_id, :title, :notes, :tags, :is_private, :language])
    |> validate_length(:notes, max: 1024)
  end
end
