defmodule Linkhut.Repo.Migrations.ConsolidateUserTypeToActive do
  use Ecto.Migration

  def up do
    # Create subscriptions for active_paying users who don't already have one.
    # Must run BEFORE the type backfill since we need to identify active_paying users.
    execute("""
    INSERT INTO subscriptions (user_id, plan, status, inserted_at, updated_at)
    SELECT u.id, 'supporter', 'active', NOW(), NOW()
    FROM users u
    LEFT JOIN subscriptions s ON s.user_id = u.id
    WHERE u.type = 'active_paying' AND s.id IS NULL
    """)

    # Backfill: convert old type values to 'active'
    execute("UPDATE users SET type = 'active' WHERE type IN ('active_free', 'active_paying')")
  end

  def down do
    # Rolling back loses the free/paying distinction in user.type.
    # The subscriptions table still preserves who had a subscription.
    # We don't delete subscriptions created in up — they remain valid data.
    execute("UPDATE users SET type = 'active_free' WHERE type = 'active'")
  end
end
