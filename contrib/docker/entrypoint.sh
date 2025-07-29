#! /bin/sh

# Wait until Postgres is ready
until pg_isready -U "${POSTGRES_USER}" -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}"
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

bin/migrate
bin/server
