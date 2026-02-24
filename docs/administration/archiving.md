# Archiving

Linkhut can capture point-in-time snapshots of bookmarked pages using
[SingleFile](https://github.com/nicktogo/single-file-cli). Snapshots are stored
locally and can be viewed, downloaded, or listed per bookmark.

## Configuration

Archiving is configured under `config :linkhut, Linkhut, archiving: [...]`.

| Key                | Type       | Default    | Description |
|--------------------|------------|------------|-------------|
| `mode`             | atom       | `:disabled` | Controls who can use archiving (see below). |
| `data_dir`         | string     | `""`       | Directory where snapshot files are stored. |
| `serve_host`       | string     | `nil`      | Hostname used when serving snapshots. Falls back to the request host. |
| `storage`          | module     | `Storage.Local` | Storage backend module. |
| `legacy_data_dirs` | list       | `[]`       | Additional directories to accept when resolving or deleting existing snapshots (useful during data directory migrations). |

### Modes

- **`:disabled`** — Archiving is completely off. No snapshots are created or
  served. This is the default.
- **`:limited`** — Archiving is available only to paying users.
- **`:enabled`** — Archiving is available to all active users.

### Environment variables

In `runtime.exs`, the following environment variable is read:

- `ARCHIVING_DATA_DIR` — maps to the `data_dir` config key.

## Security considerations

### SSRF protection

Before crawling a URL, Linkhut resolves its hostname and checks the resulting IP
against a comprehensive list of reserved/non-routable address ranges (RFC 1918,
link-local, loopback, CGN, cloud metadata, etc.). This prevents bookmarks from
being used to probe internal services.

However, SingleFile runs as a separate process and performs its own DNS
resolution. This leaves a small window for
[DNS rebinding](https://en.wikipedia.org/wiki/DNS_rebinding) attacks, where a
hostname resolves to a public IP during validation but is changed to an internal
IP before SingleFile fetches it.

**Recommendation:** Run crawler workers in a network-isolated environment (e.g.,
a container or network namespace with no access to internal services or cloud
metadata endpoints like `169.254.169.254`). This is the primary defense against
DNS rebinding and other SSRF bypass techniques.

### Snapshot serving

Snapshots are served in a sandboxed iframe with a restrictive Content Security
Policy. Access to snapshot content requires a short-lived token (15 minutes)
generated per view. The token is verified independently of the user session,
allowing the snapshot to be served from a separate host if configured via
`serve_host`.
