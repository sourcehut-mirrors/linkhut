defmodule Linkhut.Moderation.Entry do
  use Ecto.Schema

  import Ecto.Changeset
  alias Linkhut.Accounts.User

  schema "moderation_entries" do
    belongs_to :user, User

    field :action, Ecto.Enum, values: [:ban, :unban]
    field :reason, :string

    field :username, :string, virtual: true
    timestamps(type: :utc_datetime, updated_at: false)
  end

  defp changeset(user, attrs) do
    Ecto.build_assoc(user, :moderation_entries)
    |> cast(attrs, [:reason])
    |> validate_length(:reason, max: 1024)
  end

  def ban_changeset(user, attrs \\ %{}) do
    changeset(user, attrs)
    |> put_change(:action, :ban)
  end

  def unban_changeset(user, attrs \\ %{}) do
    changeset(user, attrs)
    |> put_change(:action, :unban)
  end
end
