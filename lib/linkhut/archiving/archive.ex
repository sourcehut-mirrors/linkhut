defmodule Linkhut.Archiving.Archive do
  @moduledoc "Represents a single archiving attempt for a link."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Archiving.{SchemaHelpers, Snapshot}

  @type t :: Ecto.Schema.t()

  schema "archives" do
    # Raw fields instead of belongs_to — links can be deleted independently,
    # so we don't want Ecto association constraints here.
    field :link_id, :id
    field :user_id, :id
    field :job_id, :id
    field :url, :string
    field :final_url, :string

    field :state, Ecto.Enum,
      values: [:active, :failed, :pending_deletion],
      default: :active

    field :preflight_meta, :map
    field :steps, {:array, :map}, default: []
    field :error, :string

    has_many :snapshots, Snapshot

    timestamps(type: :utc_datetime)
  end

  @castable_fields [
    :link_id,
    :user_id,
    :job_id,
    :url,
    :final_url,
    :state,
    :preflight_meta,
    :steps,
    :error
  ]

  @doc false
  def changeset(archive, attrs) do
    archive
    |> cast(attrs, @castable_fields)
    |> validate_required([:url, :link_id, :user_id])
    |> SchemaHelpers.normalize_json_fields([:preflight_meta, :steps])
  end
end
