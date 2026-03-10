defmodule Linkhut.SubscriptionsTest do
  use Linkhut.DataCase, async: true

  import Linkhut.Factory

  alias Linkhut.Subscriptions
  alias Linkhut.Subscriptions.Subscription

  describe "create_subscription/1" do
    test "creates with valid attrs" do
      user = insert(:user)

      assert {:ok, %Subscription{} = sub} =
               Subscriptions.create_subscription(%{
                 user_id: user.id,
                 plan: :supporter,
                 status: :active
               })

      assert sub.user_id == user.id
      assert sub.plan == :supporter
      assert sub.status == :active
    end

    test "fails without required fields" do
      assert {:error, changeset} = Subscriptions.create_subscription(%{})
      errors = errors_on(changeset)
      assert "can't be blank" in errors.user_id
      assert "can't be blank" in errors.plan
      assert "can't be blank" in errors.status
    end

    test "fails with invalid plan" do
      user = insert(:user)

      assert {:error, changeset} =
               Subscriptions.create_subscription(%{
                 user_id: user.id,
                 plan: :bogus,
                 status: :active
               })

      assert "is invalid" in errors_on(changeset).plan
    end

    test "fails with invalid status" do
      user = insert(:user)

      assert {:error, changeset} =
               Subscriptions.create_subscription(%{
                 user_id: user.id,
                 plan: :supporter,
                 status: :bogus
               })

      assert "is invalid" in errors_on(changeset).status
    end

    test "enforces unique constraint on user_id" do
      user = insert(:user)
      insert(:subscription, user_id: user.id)

      assert {:error, changeset} =
               Subscriptions.create_subscription(%{
                 user_id: user.id,
                 plan: :supporter,
                 status: :active
               })

      assert "has already been taken" in errors_on(changeset).user_id
    end
  end

  describe "update_subscription/2" do
    test "updates status to canceled" do
      user = insert(:user)

      {:ok, sub} =
        Subscriptions.create_subscription(%{user_id: user.id, plan: :supporter, status: :active})

      assert {:ok, updated} = Subscriptions.update_subscription(sub, %{status: :canceled})
      assert updated.status == :canceled
    end
  end

  describe "get_active_subscription/1" do
    test "returns active subscription" do
      user = insert(:user)
      insert(:subscription, user_id: user.id, plan: :supporter, status: :active)

      assert %Subscription{plan: :supporter} = Subscriptions.get_active_subscription(user)
    end

    test "returns nil for canceled subscription" do
      user = insert(:user)
      insert(:subscription, user_id: user.id, plan: :supporter, status: :canceled)

      assert Subscriptions.get_active_subscription(user) == nil
    end

    test "returns nil for user with no subscription" do
      user = insert(:user)
      assert Subscriptions.get_active_subscription(user) == nil
    end

    test "accepts raw user_id" do
      user = insert(:user)
      insert(:subscription, user_id: user.id, plan: :supporter, status: :active)

      assert %Subscription{} = Subscriptions.get_active_subscription(user.id)
    end

    test "returns nil for non-user argument" do
      assert Subscriptions.get_active_subscription(nil) == nil
    end
  end

  describe "active_plan/1" do
    test "returns plan for active subscription" do
      user = insert(:user)
      insert(:subscription, user_id: user.id, plan: :supporter, status: :active)

      assert Subscriptions.active_plan(user) == :supporter
    end

    test "returns :free for no subscription" do
      user = insert(:user)
      assert Subscriptions.active_plan(user) == :free
    end

    test "returns :free for canceled subscription" do
      user = insert(:user)
      insert(:subscription, user_id: user.id, plan: :supporter, status: :canceled)

      assert Subscriptions.active_plan(user) == :free
    end
  end
end
