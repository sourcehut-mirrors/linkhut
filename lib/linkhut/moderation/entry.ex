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

  def changeset(user, attrs) do
    %__MODULE__{}
    |> cast(Map.put(attrs, :user_id, user.id), [:user_id, :reason])
    |> validate_required([:user_id])
    |> validate_length(:reason, max: 1024)
    |> assoc_constraint(:user, message: "No user found matching provided username")
  end

  def ban_changeset(user, attrs \\ %{}) do
    changeset =
      changeset(user, attrs)
      |> put_change(:action, :ban)

    if user.is_banned do
      changeset
      |> add_error(:username, "User is already banned")
    else
      changeset
    end
  end

  def unban_changeset(user, attrs \\ %{}) do
    changeset =
      changeset(user, attrs)
      |> put_change(:action, :unban)

    if !user.is_banned do
      changeset
      |> add_error(:username, "User is already unbanned")
    else
      changeset
    end
  end
end
