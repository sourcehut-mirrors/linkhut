defmodule Linkhut.Jobs.Import do
  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  schema "imports" do
    field :user_id, :id
    field :job_id, :id

    field :state, Ecto.Enum,
      values: [:in_progress, :complete, :failed],
      default: :in_progress

    field :total, :integer
    field :saved, :integer
    field :failed, :integer

    embeds_many :failed_records, Record do
      field :url, :string
      field :title, :string
      field :notes, :string
      field :tags, {:array, :string}
      field :is_private, :boolean
      field :inserted_at, :utc_datetime
      field :errors, {:map, {:array, :string}}
    end

    belongs_to :user, User, define_field: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(import, attrs, opts \\ []) do
    import
    |> cast(
      attrs,
      [:user_id, :job_id, :state, :total, :saved, :failed],
      opts
    )
    |> cast_embed(:failed_records, with: &record_changeset/2)
    |> validate_required([:user_id, :job_id])
  end

  def record_changeset(record, attrs \\ %{}) do
    record
    |> cast(attrs, [:url, :title, :notes, :tags, :is_private, :inserted_at, :errors])
  end
end
