#!/bin/sh
set -eu
cd "$(dirname "$0")"
dump=${1:?Usage: sh restore-check.sh /absolute/path/database.dump}
test -f "$dump"
restore_db="fray_restore_$(date +%s)_$$"
docker compose exec -T db createdb -U postgres -O fray "$restore_db"
trap 'docker compose exec -T db dropdb -U postgres "$restore_db"' EXIT HUP INT TERM
docker compose exec -T db pg_restore -U postgres --exit-on-error -d "$restore_db" < "$dump"
docker compose exec -T db psql -U postgres -d "$restore_db" -v ON_ERROR_STOP=1 \
  -c 'SELECT count(*) AS users FROM auth_user;' \
  -c 'SELECT count(*) AS entries FROM tracker_timeentry;'
printf 'Restore check passed in a separate temporary database; live data was not changed.\n'
