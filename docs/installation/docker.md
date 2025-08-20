# Installation with Docker

1. Download the [`docker-compose.yml`](https://git.sr.ht/~mlb/linkhut/tree/master/contrib/docker/docker-compose.yml) and
[`.env`](https://git.sr.ht/~mlb/linkhut/tree/master/contrib/docker/sample.env) file
2. Edit the `.env` file so that it fits your needs.
3. Run `docker compose up -d`

# Finalize installation

## Create your first user

If your instance is up and running, you can create your first user with administrative rights with the following task:

```shell
$ docker exec -it linkhut-1 bin/linkhut_ctl user new <username> <your@emailaddress> --admin
```
