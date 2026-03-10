defmodule Linkhut.Subscriptions.Subscription do
  @moduledoc "A user's subscription to a plan."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  schema "subscriptions" do
    belongs_to :user, User
    field :plan, Ecto.Enum, values: [:supporter]
    field :status, Ecto.Enum, values: [:active, :canceled]

    timestamps(type: :utc_datetime)
  end

  @required_fields [:user_id, :plan, :status]

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:user_id)
  end
end
