#!/bin/sh
set -eu
umask 077
cd "$(dirname "$0")"
. ./compose-helpers.sh
backup_root=${1:?Usage: sh backup.sh /absolute/private/backup-directory}
case "$backup_root" in /*) ;; *) echo 'Use an absolute backup directory.' >&2; exit 1;; esac
mkdir -p "$backup_root"
destination=$(mktemp -d "$backup_root/fray-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
compose exec -T db sh -c 'exec pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --format=custom' > "$destination/database.dump.partial"
mv "$destination/database.dump.partial" "$destination/database.dump"
cp "$compose_env" "$destination/deployment.env"
cp "$compose_file" "$destination/compose.yaml"
compose images --format json > "$destination/images.json"
(cd "$destination" && sha256sum database.dump deployment.env compose.yaml > SHA256SUMS)
printf 'Backup complete: %s\nContains private data and keys; encrypt off-site copies.\n' "$destination"
