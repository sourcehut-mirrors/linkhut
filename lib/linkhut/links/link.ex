defmodule Linkhut.Links.Link do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Tags

  @primary_key false
  schema "links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    belongs_to :user, User, define_field: false
    field :title, :string
    field :notes, :string, default: ""
    field :tags, Tags
    field :is_private, :boolean, default: false
    field :language, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :user_id, :title, :notes, :tags, :is_private, :inserted_at])
    |> validate_required([:url, :user_id, :title, :tags, :is_private])
    |> validate_length(:url, max: 2048)
    |> validate_length(:title, max: 255)
    |> validate_length(:notes, max: 1024)
    |> unique_constraint(:url, name: :links_pkey)
  end
end
