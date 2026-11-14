#!/bin/sh
set -eu
cd "$(dirname "$0")"
. ./compose-helpers.sh
dump=${1:?Usage: sh restore-check.sh /absolute/path/database.dump}
test -f "$dump"
restore_db="fray_restore_$(date +%s)_$$"
compose exec -T db createdb -U postgres -O fray "$restore_db"
trap 'compose exec -T db dropdb -U postgres "$restore_db"' EXIT HUP INT TERM
compose exec -T db pg_restore -U postgres --exit-on-error -d "$restore_db" < "$dump"
compose exec -T db psql -U postgres -d "$restore_db" -v ON_ERROR_STOP=1 \
  -c 'SELECT count(*) AS users FROM auth_user;' \
  -c 'SELECT count(*) AS entries FROM tracker_timeentry;'
# Read through Django using the restored database and current encryption key.
# Decrypt seeds without printing them; a backup without its MFA key is incomplete.
compose exec -T -e "FRAY_DB_NAME=$restore_db" api python manage.py shell -c '
from tracker.models import Authenticator, TimeEntry, ProjectMember, EntryReceipt
for device in Authenticator.objects.iterator():
    device.get_key()
print("Restored database readable; MFA keys decrypt; entries:", TimeEntry.objects.count(), "memberships:", ProjectMember.objects.count(), "receipts:", EntryReceipt.objects.count())
'
printf 'Restore check passed in a separate temporary database; live data was not changed.\n'
