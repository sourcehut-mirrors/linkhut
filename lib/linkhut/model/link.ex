defmodule Linkhut.Model.Link do
  alias Linkhut.Repo

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    field :title, :string
    field :notes, :string
    field :tags, Linkhut.Model.Tags
    field :is_private, :boolean, default: false
    field :language, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :user_id, :title, :notes, :tags, :is_private])
    |> validate_required([:url, :user_id, :title, :notes, :tags, :is_private])
    |> validate_length(:notes, max: 1024)
    |> unique_constraint(:url, name: :links_pkey)
  end
end
