defmodule Linkhut.Archiving.Archive do
  @moduledoc "Represents a single archiving attempt for a link."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Archiving.{SchemaHelpers, Snapshot, Steps}

  @type t :: Ecto.Schema.t()

  schema "archives" do
    # Raw fields instead of belongs_to — links can be deleted independently,
    # so we don't want Ecto association constraints here.
    field :link_id, :id
    field :user_id, :id
    field :url, :string
    field :final_url, :string

    field :state, Ecto.Enum,
      values: [:pending, :processing, :complete, :failed, :pending_deletion],
      default: :pending

    field :preflight_meta, :map
    field :steps, {:array, :map}, default: []
    field :error, :string

    # Managed by Archiving.recompute_archive_size*/1 — not in @castable_fields.
    field :total_size_bytes, :integer, default: 0

    # Managed by optimistic_lock/1 — not in @castable_fields.
    field :lock_version, :integer, default: 0

    has_many :snapshots, Snapshot

    timestamps(type: :utc_datetime)
  end

  @castable_fields [
    :link_id,
    :user_id,
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
    |> optimistic_lock(:lock_version)
    |> maybe_seed_created_step()
    |> SchemaHelpers.normalize_json_fields([:preflight_meta, :steps])
  end

  defp maybe_seed_created_step(%{data: %{id: nil}} = changeset) do
    steps = get_field(changeset, :steps) || []

    if steps == [] do
      put_change(changeset, :steps, Steps.append_step([], "created", %{"msg" => "created"}))
    else
      changeset
    end
  end

  defp maybe_seed_created_step(changeset), do: changeset
end
