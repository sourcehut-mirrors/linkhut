defmodule Linkhut.Archiving.Snapshot do
  @moduledoc "A point-in-time capture of a bookmarked page."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.User
  alias Linkhut.Archiving.{Archive, SchemaHelpers}
  alias Linkhut.Links.Link

  @type t :: Ecto.Schema.t()

  schema "snapshots" do
    field :link_id, :id
    field :user_id, :id
    field :job_id, :id
    field :archive_id, :id
    field :type, :string

    field :state, Ecto.Enum,
      values: [:pending, :crawling, :complete, :failed, :pending_deletion],
      default: :pending

    field :crawl_info, :map
    field :response_code, :integer
    field :file_size_bytes, :integer
    field :processing_time_ms, :integer
    field :retry_count, :integer, default: 0
    field :failed_at, :utc_datetime
    field :storage_key, :string
    field :archive_metadata, :map

    belongs_to :link, Link, define_field: false
    belongs_to :user, User, define_field: false
    belongs_to :archive, Archive, define_field: false

    timestamps(type: :utc_datetime)
  end

  @updatable_fields [
    :job_id,
    :archive_id,
    :type,
    :state,
    :crawl_info,
    :response_code,
    :file_size_bytes,
    :processing_time_ms,
    :retry_count,
    :failed_at,
    :storage_key,
    :archive_metadata
  ]

  @doc false
  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:link_id, :user_id] ++ @updatable_fields)
    |> validate_required([:link_id, :user_id])
    |> SchemaHelpers.normalize_json_fields([:archive_metadata, :crawl_info])
  end

  @doc false
  def update_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @updatable_fields)
    |> SchemaHelpers.normalize_json_fields([:archive_metadata, :crawl_info])
  end
end
