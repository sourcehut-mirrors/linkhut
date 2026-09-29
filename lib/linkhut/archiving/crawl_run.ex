defmodule Linkhut.Archiving.CrawlRun do
  @moduledoc "Represents a single crawl run (archiving attempt) for a link."

  use Ecto.Schema
  alias Linkhut.Archiving.Log.Event

  @type t :: Ecto.Schema.t()

  schema "crawl_runs" do
    field :link_id, :id

    has_many :events, Event, preload_order: [asc: :inserted_at, asc: :id]

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
