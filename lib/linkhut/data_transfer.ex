defmodule Linkhut.DataTransfer do
  @moduledoc """
  Module for importing and exporting links.
  """

  import Ecto.Query

  alias Linkhut.Accounts.User
  alias Linkhut.DataTransfer.Import
  alias Linkhut.DataTransfer.Parser
  alias Linkhut.DataTransfer.Parsers
  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Repo

  @parsers [Parsers.Netscape]

  @type success :: {:ok, Linkhut.Links.Link.t()}
  @type failure :: {:error, String.t() | %Ecto.Changeset{}}

  @spec parse(String.t()) :: {:ok, [Parser.bookmark()]} | {:error, :unsupported_format}
  def parse(document) do
    case detect_parser(document) do
      {:ok, parser} -> parser.parse_document(document)
      :error -> {:error, :unsupported_format}
    end
  end

  @spec save_bookmark(User.t(), Parser.bookmark(), map()) :: success | failure
  def save_bookmark(user, {:ok, attrs}, %{"is_private" => "true"}) do
    Links.create_link(user, Map.replace(attrs, :is_private, true))
  end

  def save_bookmark(user, {:ok, attrs}, _overrides) do
    Links.create_link(user, attrs)
  end

  def save_bookmark(_user, {:error, msg}, _overrides) do
    {:error, msg}
  end

  defp detect_parser(document) do
    case Enum.find(@parsers, & &1.can_parse?(document)) do
      nil -> :error
      parser -> {:ok, parser}
    end
  end

  @spec export(User.t()) :: [Linkhut.Links.Link.t()]
  def export(user) do
    Links.all(user)
  end

  @doc """
  Streams a user's links inside a transaction, passing the stream to the
  given callback. This avoids loading all links into memory at once.
  """
  @spec export_stream(User.t(), (Enumerable.t() -> result)) :: result when result: var
  def export_stream(user, callback) do
    query =
      from(l in Link,
        where: l.user_id == ^user.id,
        order_by: [desc: l.inserted_at]
      )

    Repo.transaction(fn ->
      query
      |> Repo.stream()
      |> callback.()
    end)
    |> elem(1)
  end

  # Import record CRUD

  @spec create_import(User.t(), Oban.Job.t(), map(), map()) ::
          {:ok, Import.t()} | {:error, Ecto.Changeset.t()}
  def create_import(%User{} = user, job, overrides, attrs \\ %{}) do
    %Import{user_id: user.id, job_id: job.id, overrides: overrides}
    |> Import.changeset(attrs)
    |> Repo.insert()
  end

  @spec get_import(integer(), integer()) :: Import.t() | nil
  def get_import(user_id, job_id) do
    Import
    |> Repo.get_by(user_id: user_id, job_id: job_id)
  end

  @spec update_import(Import.t(), map()) :: {:ok, Import.t()} | {:error, Ecto.Changeset.t()}
  def update_import(%Import{} = import, attrs) do
    import
    |> Import.changeset(attrs)
    |> Repo.update()
  end

  @spec has_active_import?(integer()) :: boolean()
  def has_active_import?(user_id) do
    Import
    |> where(user_id: ^user_id)
    |> where([i], i.state in [:queued, :in_progress])
    |> Repo.exists?()
  end
end
