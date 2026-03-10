defmodule Linkhut.Subscriptions do
  @moduledoc "Manages user subscriptions."

  alias Linkhut.Accounts.User
  alias Linkhut.Repo
  alias Linkhut.Subscriptions.Subscription

  @doc "Creates a subscription from the given attrs."
  @spec create_subscription(map()) :: {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def create_subscription(attrs) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing subscription."
  @spec update_subscription(Subscription.t(), map()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns the active subscription for a user, or nil."
  @spec get_active_subscription(User.t() | integer()) :: Subscription.t() | nil
  def get_active_subscription(%User{id: user_id}), do: get_active_subscription(user_id)

  def get_active_subscription(user_id) when is_integer(user_id) do
    Repo.get_by(Subscription, user_id: user_id, status: :active)
  end

  def get_active_subscription(_), do: nil

  @doc """
  Returns the plan atom for a user's active subscription.
  Returns `:free` if no active subscription exists.
  """
  @spec active_plan(User.t() | integer()) :: atom()
  def active_plan(user_or_id) do
    case get_active_subscription(user_or_id) do
      nil -> :free
      sub -> sub.plan
    end
  end
end
