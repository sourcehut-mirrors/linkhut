# Archiving

Linkhut can capture point-in-time snapshots of bookmarked pages using
[SingleFile](https://github.com/nicktogo/single-file-cli). Snapshots can be
stored on the local filesystem or in S3-compatible object storage, and can be
viewed, downloaded, or listed per bookmark.

## Configuration

Archiving is configured under `config :linkhut, Linkhut.Archiving, [...]`.

| Key                | Type       | Default    | Description |
|--------------------|------------|------------|-------------|
| `mode`             | atom       | `:disabled` | Controls who can use archiving (see below). |
| `data_dir`         | string     | `""`       | Directory where snapshot files are stored. |
| `serve_host`       | string     | `nil`      | Hostname used when serving snapshots. Falls back to the request host. |
| `storage`          | module     | `Storage.Local` | Storage backend module. |
| `legacy_data_dirs` | list       | `[]`       | Additional directories to accept when resolving or deleting existing snapshots (useful during data directory migrations). |

### Local storage

Configuration under `config :linkhut, Linkhut.Archiving.Storage.Local, [...]`:

| Key            | Type | Default | Description |
|----------------|------|---------|-------------|
| `compression`  | atom | `:gzip` | Compression algorithm for new snapshots (`:none` or `:gzip`). |

### S3 storage

Configuration under `config :linkhut, Linkhut.Archiving.Storage.S3, [...]`:

| Key                  | Type    | Default          | Description |
|----------------------|---------|------------------|-------------|
| `bucket`             | string  | (required)       | S3 bucket name. |
| `region`             | string  | `"eu-central-1"` | AWS region. |
| `endpoint`           | string  | (required)       | S3 endpoint hostname (e.g. `s3.eu-central-1.amazonaws.com` or a MinIO host). |
| `access_key_id`      | string  | (required)       | AWS access key ID. |
| `secret_access_key`  | string  | (required)       | AWS secret access key. |
| `scheme`             | string  | `"https://"`     | URL scheme for the endpoint. |
| `port`               | integer | `443`            | Port for the endpoint. |
| `presign_ttl`        | integer | `900`            | Presigned URL expiry in seconds. |
| `compression`        | atom    | `:gzip`          | Compression algorithm for new snapshots (`:none` or `:gzip`). |

To use S3 storage, set `storage: Linkhut.Archiving.Storage.S3` in the
`Linkhut.Archiving` config. Both backends can coexist — the dispatch layer
routes resolve and delete operations based on the storage key prefix regardless
of the active backend.

### Modes

- **`:disabled`** — Archiving is completely off. No snapshots are created or
  served. This is the default.
- **`:limited`** — Archiving is available only to paying users.
- **`:enabled`** — Archiving is available to all active users.

### Environment variables

In `runtime.exs`, the following environment variables are read:

**General:**

| Variable | Config key | Type | Default | Description |
|---|---|---|---|---|
| `ARCHIVING_MODE` | `:mode` | `"enabled"`, `"limited"`, or `"disabled"` | `"disabled"` | Controls who can use archiving. |
| `ARCHIVING_STORAGE` | `:storage` | `"local"` or `"s3"` | `"local"` | Storage backend for new snapshots. |
| `ARCHIVING_DATA_DIR` | `:data_dir` | path string | (none) | Directory where local snapshot files are stored. |
| `ARCHIVING_STAGING_DIR` | `:staging_dir` | path string | (none) | Temporary directory for crawler output before storage. Defaults to `data_dir` if unset. |
| `ARCHIVING_SERVE_HOST` | `:serve_host` | hostname string | (none) | Dedicated hostname for serving archived HTML. |
| `ARCHIVING_MAX_FILE_SIZE` | `:max_file_size` | integer (bytes) | `70000000` | Maximum size of archived files. |
| `ARCHIVING_USER_AGENT_SUFFIX` | `:user_agent_suffix` | string | (none) | Appended to crawler User-Agent. |

**Local storage:**

| Variable | Config key | Type | Default | Description |
|---|---|---|---|---|
| `ARCHIVING_LOCAL_COMPRESSION` | `:compression` | `"none"` or `"gzip"` | `"gzip"` | Compression for new local snapshots. |

**S3 storage:**

| Variable | Config key | Type | Default | Description |
|---|---|---|---|---|
| `ARCHIVING_S3_BUCKET` | `:bucket` | string | (none) | S3 bucket name. Enables S3 config when set. |
| `ARCHIVING_S3_ENDPOINT` | `:endpoint` | hostname string | (required) | S3 endpoint hostname. |
| `ARCHIVING_S3_REGION` | `:region` | string | `"eu-central-1"` | AWS region. |
| `ARCHIVING_S3_ACCESS_KEY_ID` | `:access_key_id` | string | (none) | AWS access key ID. |
| `ARCHIVING_S3_SECRET_ACCESS_KEY` | `:secret_access_key` | string | (none) | AWS secret access key. |
| `ARCHIVING_S3_SCHEME` | `:scheme` | `"https://"` or `"http://"` | `"https://"` | URL scheme for the endpoint. |
| `ARCHIVING_S3_PORT` | `:port` | integer | `443` | Port for the endpoint. |
| `ARCHIVING_S3_PRESIGN_TTL` | `:presign_ttl` | integer (seconds) | `900` | Presigned URL expiry. |
| `ARCHIVING_S3_COMPRESSION` | `:compression` | `"none"` or `"gzip"` | `"gzip"` | Compression for new S3 snapshots. |

### Compression

When `compression` is set to `:gzip`, new snapshots with compressible content
types are gzip-compressed at rest.

- Compressed files are served with `Content-Encoding: gzip`, so browsers
  decompress them transparently.
- For local storage, downloads are decompressed before sending. For S3
  storage, downloads are served via presigned URL.
- Existing snapshots are not affected by the setting change. Use
  `mix linkhut.storage local.compress` to compress local snapshots
  retroactively.

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
