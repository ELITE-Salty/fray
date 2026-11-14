#!/bin/sh
set -eu
# psql quotes the password as a SQL literal; never interpolate it into SQL text.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 --set=app_password="$FRAY_DB_PASSWORD" <<'SQL'
CREATE ROLE fray LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER DATABASE fray OWNER TO fray;
REVOKE ALL ON DATABASE fray FROM PUBLIC;
GRANT CONNECT ON DATABASE fray TO fray;
SQL
