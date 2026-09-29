defmodule Linkhut.Archiving.Log.Event do
  @moduledoc false

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "archiving_events" do
    field :snapshot_id, :id
    field :source, :string
    field :event, :string
    field :level, Ecto.Enum, values: [:info, :warning, :error], default: :info
    field :data, :map, default: %{}

    belongs_to :crawl_run, Linkhut.Archiving.CrawlRun

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
