defmodule Linkhut.Archiving.Log do
  @moduledoc """
  Facilities for persisting archiving log events.
  """

  import Ecto.Changeset, only: [change: 1, foreign_key_constraint: 2]

  alias Linkhut.Archiving.Snapshot
  alias Linkhut.Archiving.Log.Event
  alias Linkhut.Repo

  require Logger

  @enforce_keys [:crawl_run_id]
  defstruct [:crawl_run_id, :snapshot_id, :source]

  @type t :: %__MODULE__{
          crawl_run_id: integer(),
          snapshot_id: integer() | nil,
          source: String.t() | nil
        }

  @levels Ecto.Enum.values(Event, :level)

  @doc "Returns a log handle for events about the crawl run `run_id`."
  @spec for_run(integer()) :: t()
  def for_run(run_id) when is_integer(run_id), do: %__MODULE__{crawl_run_id: run_id}

  @doc "Returns a log handle for events about a `snapshot` in the run `run_id`."
  @spec for_snapshot(Snapshot.t(), integer() | nil) :: t() | nil
  def for_snapshot(_snapshot, nil), do: nil

  def for_snapshot(%Snapshot{} = snapshot, run_id) when is_integer(run_id) do
    %__MODULE__{crawl_run_id: run_id, snapshot_id: snapshot.id, source: snapshot.source}
  end

  @doc """
  Appends an event to the crawl run `log` points at.

  Appending is best-effort. A failure is logged and `:ok` is returned.

  ## Options

    - `:level`: `:info` (default), `:warning` or `:error`
    - `:source`: overrides the handle's source, for a run-level event about
      one crawler
  """
  @spec append(t() | nil, String.t(), map(), keyword()) :: :ok
  def append(log, event, data \\ %{}, opts \\ [])
  def append(nil, _event, _data, _opts), do: :ok

  def append(%__MODULE__{} = log, event, data, opts) when is_binary(event) and is_map(data) do
    level = Keyword.get(opts, :level, :info)

    if level not in @levels do
      raise ArgumentError, "unknown level #{inspect(level)}, expected one of #{inspect(@levels)}"
    end

    insert(%Event{
      crawl_run_id: log.crawl_run_id,
      snapshot_id: log.snapshot_id,
      source: Keyword.get(opts, :source, log.source),
      event: event,
      level: level,
      data: Map.reject(data, fn {_key, value} -> is_nil(value) end)
    })
  end

  defp insert(event) do
    event
    |> change()
    |> foreign_key_constraint(:crawl_run_id)
    |> Repo.insert()

    :ok
  rescue
    error ->
      Logger.warning(
        "Failed to append #{event.event} to crawl_run #{event.crawl_run_id}: #{inspect(error)}"
      )

      :ok
  end
end
