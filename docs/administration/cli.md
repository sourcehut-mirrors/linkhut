# CLI

Every command should be ran as the `linkhut` user from it's home directory. For example if you are superuser, you would have to wrap the command in `su linkhut -s $SHELL -lc "$COMMAND"`.

> #### Note about `MIX_ENV` when using Mix {: .info}
>
> The `mix` command should be prefixed with the name of environment your linkhut server is running in, usually it's `MIX_ENV=prod`


## User management


### Create a user

<!-- tabs-open -->
### CLI

```shell
./bin/linkhut_ctl user new <username> <email> [option ...]
```

### Mix

```shell
mix linkhut.user new <username> <email> [option ...]
```
<!-- tabs-close -->


#### Options
- `--password <password>` - the user's password
- `--admin`/`--no-admin` - whether the user should be an admin
- `-y`, `--assume-yes`/`--no-assume-yes` - whether to assume yes to all questions


## Storage management


### Show storage stats

<!-- tabs-open -->
### CLI

```shell
./bin/linkhut_ctl storage
```

### Mix

```shell
mix linkhut.storage
```
<!-- tabs-close -->


### Compress local snapshots

Gzip-compress uncompressed local snapshots.

<!-- tabs-open -->
### CLI

```shell
./bin/linkhut_ctl storage local.compress [--dry-run]
```

### Mix

```shell
mix linkhut.storage local.compress [--dry-run]
```
<!-- tabs-close -->


### Decompress local snapshots

Decompress gzip-compressed local snapshots.

<!-- tabs-open -->
### CLI

```shell
./bin/linkhut_ctl storage local.decompress [--dry-run]
```

### Mix

```shell
mix linkhut.storage local.decompress [--dry-run]
```
<!-- tabs-close -->

