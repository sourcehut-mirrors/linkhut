defmodule Linkhut.DataTransfer.Import do
  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  schema "imports" do
    field :user_id, :id
    field :job_id, :id
    field :file, :string
    field :overrides, :map

    field :state, Ecto.Enum,
      values: [:queued, :in_progress, :complete, :failed, :canceled],
      default: :queued

    field :total, :integer
    field :saved, :integer, default: 0
    field :failed, :integer, default: 0
    field :invalid, :integer, default: 0

    embeds_many :failed_records, Record do
      field :url, :string
      field :title, :string
      field :notes, :string
      field :tags, {:array, :string}
      field :is_private, :boolean
      field :inserted_at, :utc_datetime
      field :errors, {:map, {:array, :string}}
    end

    field :invalid_entries, {:array, :string}

    belongs_to :user, User, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(import, attrs, opts \\ []) do
    import
    |> cast(
      attrs,
      [:user_id, :job_id, :file, :state, :total, :saved, :invalid, :failed, :invalid_entries],
      opts
    )
    |> cast_embed(:failed_records, with: &record_changeset/2)
    |> validate_required([:user_id, :job_id])
  end

  def record_changeset(record, attrs \\ %{}) do
    record
    |> cast(attrs, [:url, :title, :notes, :tags, :is_private, :inserted_at, :errors])
  end

  @doc "Returns the number of bookmarks that have been imported (or attempted) so far"
  def processed_count(%__MODULE__{saved: s, failed: f, invalid: i}), do: s + f + i
end
