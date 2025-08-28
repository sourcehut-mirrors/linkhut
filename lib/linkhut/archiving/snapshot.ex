defmodule Linkhut.Archiving.Snapshot do
  @moduledoc "A point-in-time capture of a bookmarked page."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Links.Link

  @type t :: Ecto.Schema.t()

  schema "snapshots" do
    field :link_id, :id
    field :job_id, :id
    field :type, :string

    field :state, Ecto.Enum,
      values: [:in_progress, :complete, :failed],
      default: :in_progress

    field :crawl_info, :map
    field :response_code, :integer
    field :file_size_bytes, :integer
    field :processing_time_ms, :integer
    field :retry_count, :integer, default: 0
    field :failed_at, :utc_datetime
    field :storage_key, :string
    field :archive_metadata, :map

    belongs_to :link, Link, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :link_id,
      :job_id,
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
    ])
    |> validate_required([:link_id, :job_id])
  end
end
