# Moderation

## Account-age quarantine

Links from recently-created accounts are hidden from public discovery surfaces
(recent, popular, search, tag filtering, and the URL detail timeline). This
reduces spam visibility without affecting the user's own experience as their
bookmarks remain visible on their profile page and in their own search results.

User profile pages, URL aggregate stats, and API endpoints are unaffected.

## Configuration

Moderation is configured under `config :linkhut, Linkhut.Moderation, [...]`.

| Key                | Type    | Default | Description |
|--------------------|---------|---------|-------------|
| `account_age_days` | integer | `30`    | Accounts younger than this many days are quarantined. Set to `0` to disable. |

### Environment variables

In `runtime.exs`, the following environment variables are read:

| Variable | Config key | Type | Default | Description |
|---|---|---|---|---|
| `MODERATION_ACCOUNT_AGE_DAYS` | `:account_age_days` | integer | `30` | Accounts younger than this many days are quarantined. |
