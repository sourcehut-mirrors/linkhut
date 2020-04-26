defmodule Linkhut.Model.Link do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    belongs_to :user, Linkhut.Model.User, define_field: false
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

  @doc false
  def changeset(link) do
    changeset(link, %{})
    |> (fn changeset ->
          put_change(changeset, :tags, format_tags(get_field(changeset, :tags, [])))
        end).()
  end

  @doc false
  def changeset() do
    changeset(%Linkhut.Model.Link{}, %{})
  end

  defp format_tags(tags) when is_list(tags), do: Enum.join(tags, " ")
  defp format_tags(tags) when is_binary(tags), do: tags
end
