defmodule Linkhut.Model.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "links" do
    field :description, :string
    field :is_private, :boolean, default: false
    field :tags, {:array, :string}
    field :language, :string
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true

    timestamps()
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :user_id, :description, :tags, :is_private, :language])
    |> validate_required([:url, :user_id, :description, :tags, :is_private, :language])
  end
end
