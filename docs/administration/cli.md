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

