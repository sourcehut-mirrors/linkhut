defmodule Linkhut.Links.Link do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: Ecto.Schema.t()

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Tags

  @primary_key false
  schema "links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    belongs_to :user, User, define_field: false
    field :title, :string
    field :notes, :string, default: ""
    field :tags, Tags, default: []
    field :is_private, :boolean, default: false
    field :language, :string
    field :is_unread, :boolean, default: false
    field :saves, :integer, default: 0, virtual: true
    field :score, :float, default: 0.0, virtual: true

    many_to_many :savers, User, join_through: __MODULE__, join_keys: [url: :url, user_id: :id]
    has_many :variants, __MODULE__, references: :url, foreign_key: :url

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:url, :user_id, :title, :notes, :tags, :is_private, :inserted_at, :is_unread])
    |> validate_required([:url, :user_id, :title, :is_private])
    |> validate_length(:url, max: 2048)
    |> validate_length(:title, max: 255)
    |> validate_length(:notes, max: 1024)
    |> validate_url(:url)
    |> unique_constraint(:url, name: :links_pkey)
    |> update_unread_status()
    |> update_tags()
    |> dedupe_tags()
  end

  defp update_unread_status(changeset) do
    case get_change(changeset, :is_unread) do
      nil -> changeset
      false -> force_change(changeset, :tags, remove_unread_tag(get_field(changeset, :tags, [])))
      true -> force_change(changeset, :tags, add_unread_tag(get_field(changeset, :tags, [])))
    end
  end

  defp update_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        if Enum.any?(tags, &Tags.is_unread?/1),
          do: force_change(changeset, :is_unread, true),
          else: changeset
    end
  end

  defp dedupe_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        force_change(
          changeset,
          :tags,
          Enum.uniq_by(
            tags,
            &if(Tags.is_unread?(&1), do: Tags.unread(), else: String.downcase(&1))
          )
        )
    end
  end

  defp add_unread_tag(tags), do: ["unread" | tags]
  defp remove_unread_tag(tags), do: Enum.reject(tags, &Tags.is_unread?/1)

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: nil} -> [{field, "is missing a scheme"}]
        %URI{host: nil} -> [{field, "is missing a host"}]
        _ -> []
      end
    end)
  end
end
