# FRAY web foundation — setup

This branch delivers the FRAY web milestone for independent QA: verified-email
accounts, mandatory MFA, personal tracking, shared projects, owner email invitations,
member totals, calendar, personal reports and CSV. Android/iOS and PDF/XLSX exports
are outside this milestone. The original blueprint and supplied images are retained.

## Clean checkout with Docker Compose

Requires Git, Docker Engine and Docker Compose v2 on a host able to pull public
images. There are no paid services. This starts local services, not production.

```sh
git clone https://github.com/ELITE-Salty/fray.git
cd fray
git switch feat/blu-4-web
cp .env.example .env
python3 -c 'import secrets; print(secrets.token_urlsafe(64)); print(secrets.token_urlsafe(32))'
```

Put the two **different** generated values into `FRAY_SECRET_KEY` and
`POSTGRES_PASSWORD` in `.env`. Do not commit them. Keep the secret key stable:
it protects sessions and encrypts MFA authenticator/recovery seeds. Back it up
separately from the database; replacing it requires a re-encryption migration.

```sh
docker compose up --build --wait
```

Open <http://localhost:8000>. The web container applies versioned migrations,
collects static assets, then runs Gunicorn as an unprivileged user. PostgreSQL
has no published port. Web binds only to loopback. Check readiness at `/health/`.

### Email and first sign-in

The example configuration uses the console email backend **only for local
verification**. Register with your email, then privately inspect
`docker compose logs web` for the confirmation URL. Open it and confirm. Email
links and application logs are sensitive; do not paste them into task comments.

For actual delivery, set `FRAY_EMAIL_BACKEND` to
`django.core.mail.backends.smtp.EmailBackend` and configure `EMAIL_HOST`,
`EMAIL_PORT`, `EMAIL_USE_TLS`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, and
`DEFAULT_FROM_EMAIL` for your SMTP server. No third-party account is required for
local use. Recreate web after configuration changes (`docker compose up -d web`).

After verification, sign in, re-enter your password if prompted, scan the MFA
QR code with an authenticator and enter the current code. Save the recovery
codes presented once; each works once. Password alone cannot complete subsequent
sign-ins. Password reset uses the same email delivery configuration. The profile
page links password, email, MFA and recovery management. Disabling MFA returns
the account to the enrollment gate before app access.

### Sharing a project

Only a project owner may invite members. Open the project and enter the invited
email address. SMTP sends a seven-day invitation; the recipient signs up/signs in,
verifies that email and enrolls MFA, then explicitly accepts. Opening a link alone
does not join a project. A signed-in recipient can also find invitations under
**Projects & activities**. Invitations grant no project access until acceptance.
Another verified account cannot use the link. Expired invitations require a new
invitation. Repeated acceptance is safe and never adds duplicate membership.

For the self-hosted milestone, configure your SMTP server as above before inviting.
Console email remains a local-only test option. If SMTP fails, the invitation stays
available in-app and the owner sees a failure notice. Re-enter the address after
one minute to retry the same unexpired invitation. Sending is limited to one
attempt per address per minute and at most 20 recently attempted invitations per
project per hour. Archived projects cannot invite or accept new members.

All accepted members can select the shared project for manual entries or their
own timer. Each account has its own independent timer. The project page shows
monthly completed project and member totals, including zero-time members. Dates
use each entry's recorded local date, even when members use different timezones.
A live timer joins totals only after stopping. Project names/descriptions and member
email identities are shared; individual entry descriptions, notes, times and personal
CSV/reports stay author-only. Only the owner may archive/restore the project.
Existing records and memberships are retained; removal/transfer is outside this slice.

### Tracking

1. Create a project or personal activity under **Projects & activities**, or
   choose **General work** to track without either.
2. Start a timer with a description. Refreshing, closing the browser or restarting
   web does not stop it. One timer per account is enforced in the database and
   serialized on PostgreSQL. Stop saves elapsed seconds; double starts/stops are
   idempotent. Two separate accounts have independent timers.
3. Add manual time as a duration and date, or as start/end datetimes. Select the
   end date explicitly for overnight work. Duration entries have no timestamps.
4. View your calendar, monthly entries and reports. CSV includes only your own
   work and excludes notes. Archived items retain historical records, and can be
   restored. No delete/member-removal endpoints are included.

Times use the IANA zone chosen in **Profile & security**, default
`Europe/Ljubljana`. Timed durations use UTC elapsed seconds, including DST.
Ambiguous/nonexistent local clock times are rejected: adjust the time or log a
known duration. Manual intervals must be positive and no more than 24 elapsed
hours; durations accept 1–1440 minutes. Timers may cross days. Each entry belongs
to its recorded start date; cross-midnight time is not split across reports.
Overlaps are allowed and all recorded durations count toward totals. Reports
exclude a running timer until stopped. Changing timezone does not rewrite old
dates. Timer display uses browser time; stored duration always uses server time.

## Persistence and maintenance

Data, sessions and the shared rate-limit/replay cache live in PostgreSQL's named
`fray_database` volume. `docker compose restart` and `docker compose down` retain
the volume. Never run volume removal commands on data you want to keep.

Back up with `docker compose exec -T db pg_dump -U fray -d fray > backup.sql`
(adjust user/database if customized), then store that dump and the stable secret
key securely and separately. Restore only into a **fresh empty instance**, using
`psql` after migrating the target. Do not overwrite or remove existing data or
access without the requester's approval. Production backup/restore drills,
HTTPS hosting, monitoring, retention and security review are still release work.

For an explicitly authorized HTTPS host, configure `FRAY_ALLOWED_HOSTS`, exact
`FRAY_CSRF_TRUSTED_ORIGINS`, and set `FRAY_COOKIE_SECURE=true` and
`FRAY_SSL_REDIRECT=true`. TLS must terminate at a trusted proxy. Forwarded headers
are not trusted by default. Do not expose the example HTTP configuration publicly.

## Checks

```sh
docker compose exec web python manage.py check
docker compose exec web python manage.py makemigrations --check --dry-run
docker compose exec web python manage.py test tracker --noinput
```

Tests create a separate disposable test database. The configured database user
must be able to create it (the local Compose PostgreSQL user can). Avoid pointing
tests at an existing production server. `scripts/compose-verify.sh` is for an
isolated CI checkout: it verifies clean startup, runs tests, adds a uniquely named
probe record, restarts both services and verifies the record survives. It leaves
the CI volume intact for inspection. GitHub Actions runs this on changes.

## Local Python development (optional)

Python 3.13 with venv/pip and PostgreSQL 17 is supported. SQLite is a quick local
fallback; it does not exercise PostgreSQL row-lock concurrency.

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
export FRAY_SECRET_KEY="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')"
export FRAY_DEBUG=true
export FRAY_EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
python web/manage.py migrate
python web/manage.py collectstatic --noinput
python web/manage.py runserver
```

Keep the development key stable if retaining the database. For PostgreSQL set
`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER` and
`POSTGRES_PASSWORD`; without `POSTGRES_HOST`, local SQLite is used.

The browser check demonstrates owner invitation, member acceptance, two independent
shared-project timers, correct member totals, private entry isolation, and mobile
rendering. Browser smoke checks are in `scripts/browser-smoke.cjs` (Playwright 1.62.1).
CI runs them against the Compose app and saves responsive screenshots. The
fixture script adds two isolated verified/MFA-enrolled demo accounts only to the
disposable CI database; it is not an account-creation or MFA bypass offered by
the app. Actual email verification, password login, MFA challenge/enrollment,
replay prevention and recovery are tested separately in `web/tracker/tests.py`.
Never publish the temporary browser session-state file.
