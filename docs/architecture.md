# Architecture and implementation decisions

## Current milestone

Flutter replaces the blueprint's suggested Expo client. Django replaces the suggested TypeScript API: its authentication, sessions, CSRF middleware, ORM, migrations, and management commands provide a compact backend that can run under systemd on an apt-provisioned Ubuntu VM. These are implementation choices, not changes to the product's intended privacy boundaries.

Local flow:

```text
Browser -> localhost:8080 (Python development proxy)
            |-- /                 Flutter web build
            |-- /api/*            Django on loopback :8000
            `-- /metrics          Django Prometheus endpoint
                                     |-- SQLite (development only)
                                     `-- in-process cache (development only)
```

The local proxy never serves the repository root, backend code, database, or credentials files. Flutter uses the browser's same-origin cookies; CSRF tokens are obtained before login and refreshed after session rotation. Native HTTP clients persist session/CSRF cookies in platform secure storage, bind them to the exact API origin, enforce expiry/path/secure restrictions, and send the configured API origin. No bearer tokens are stored in browser local storage.

Flutter and the API share a small JSON contract; no deployment URL is hardcoded in the web client. API and static web assets can later live behind Nginx at the same hostname. Native builds use `FRAY_API_URL` at compile time.

## Models and permission boundaries

- Django users own items and time entries.
- `Item` distinguishes `project` and `activity`; it stores metadata, color, pinned status, and archived status.
- `TimeEntry` stores its author, item, local date, IANA timezone, mode, nullable UTC timestamps, duration in whole minutes, and private notes.
- `Authenticator` extends django-otp's device and throttling primitives. Fernet encrypts its 20-byte seed. The TOTP verifier accepts a ±1 time-step clock window and remembers the consumed counter to prevent replay.
- `RecoveryCode` contains an Argon2 password hash and is removed after use. Login consumption locks the user and device rows in PostgreSQL.

Every API lookup for an item/entry includes the requesting owner/author. Creation checks ownership of the referenced item; reports filter before aggregating. There is no team endpoint or membership assumption. Database mode/duration constraints are defense in depth; author/item consistency is checked by the API and must be preserved in future import/admin code.

Timed creation locks the author before checking overlaps and inserting. PostgreSQL supplies row locking for concurrent writers; SQLite development mode does not establish the production concurrency guarantee. PostgreSQL concurrency tests are future work.

Archives remain in historical reports. Archiving blocks new entries and edits to entries on that item until it is unarchived; deletion of one's historical entry remains allowed. Items themselves are not deleted through the API.

## Authentication

`create_fray_user` is the current enrollment path. The operator supplies a password and delivers the generated authenticator seed and recovery codes privately. A successful first login proves possession of the seed or a recovery code. Email ownership is not verified yet. Public signup, self-service MFA rotation, password reset, and account deletion are not implemented.

Login requires both a valid password and a TOTP/recovery code. Django hashes passwords with Argon2. Accounts receive a 10-attempt/5-minute cache limit, plus django-otp device throttling. Production uses shared Redis; the development cache is in-process and resets on restart. Cloudflare per-client limits should supplement this account limit for the tunnel deployment to address distributed/account-targeted abuse.

All private endpoints require both an authenticated session and a verified device. Sessions last eight hours. CSRF protection remains active on login, logout, and writes. Production enables secure/HttpOnly session cookies, Strict SameSite cookies, HTTPS redirects, and HSTS. Cookies and database-backed sessions allow server-side invalidation. Logout flushes the current session; changing the password through Django invalidates existing password-session hashes.

Production refuses to boot without `FRAY_SECRET_KEY`, `FRAY_MFA_KEY`, PostgreSQL credentials, and a Redis URL. Use an independent `Fernet.generate_key()` key; losing it makes enrolled MFA secrets unrecoverable. Keep it in protected backup storage. Encryption protects seeds from a database-only leak; it does not protect against compromise of the app process or its environment.

## API contract

Paths have no trailing slash. Writes use JSON and `X-CSRFToken`. Responses are JSON unless requesting CSV. Errors include `{"error":"..."}` for application validation/authentication failures; Django's CSRF/404 handlers may return HTML, which the client handles as a generic request failure.

| Method | Path | Behavior |
|---|---|---|
| GET | `/api/auth/csrf` | Set CSRF cookie; return `csrfToken` |
| POST | `/api/auth/login` | `{email,password,code}`; return name/email and rotated CSRF token |
| POST | `/api/auth/logout` | Destroy current session |
| GET | `/api/auth/me` | Current MFA-verified identity |
| GET / POST | `/api/items` | Own items / create item |
| PATCH | `/api/items/:uuid` | Edit metadata, pin, or archive own item |
| GET | `/api/entries?month=YYYY-MM` | Own entries within the month |
| POST | `/api/entries` | Create a validated entry |
| PATCH / DELETE | `/api/entries/:uuid` | Replace entry fields / delete own entry |
| GET | `/api/reports/monthly?month=YYYY-MM` | Own totals grouped by item |
| GET | `/api/reports/monthly?month=YYYY-MM&format=csv` | Summary CSV, minutes, no notes |
| GET | `/api/health` | Database and cache readiness; 503 when unavailable |
| GET | `/metrics` | Prometheus counters/histograms; restrict to monitoring in deployment |

Item creation example:

```json
{"name":"Faculty project","kind":"project","description":"VM automation","color":"#7153E8","pinned":true}
```

Duration-only entry (use a real item UUID):

```json
{"item_id":"<uuid>","date":"2026-11-13","timezone":"Europe/Ljubljana","mode":"duration","minutes":90,"notes":"Prepared the deployment plan"}
```

Timed entry:

```json
{"item_id":"<uuid>","date":"2026-11-13","timezone":"Europe/Ljubljana","mode":"timed","start":"2026-11-13T23:30:00+01:00","end":"2026-11-14T00:30:00+01:00","notes":"Evening study"}
```

The server calculates timed duration; submitted `minutes` is ignored in timed mode. Timestamp offsets are mandatory. The date must match the start in the supplied timezone. Overlap errors return 409; duration/shape errors return 400. Unknown or inaccessible UUIDs return 404. Unauthorized sessions return 401, missing CSRF returns 403, and login throttling returns 429.

CSV escapes spreadsheet formulas in item names. Reports include archived work, never another user's entries, and never notes in this first release.

## Observability

`fray_http_requests_total{route,method,status}` and `fray_http_request_seconds{route}` use bounded route templates rather than item UUIDs. The library also exposes process metrics. Metrics do not label users, notes, email addresses, or secrets. The current registry is per process: use **one Gunicorn worker with threads** initially, or implement Prometheus multiprocess aggregation before scaling to multiple workers. Do not assume the current counters aggregate across processes.

Health checks confirm database access and a cache round trip. Audit logs record authentication outcomes and item/entry writes by opaque ID; there is no permanent database audit-history UI yet. The local launcher prints logs to the terminal. The Docker deployment supplies rotated container logs, Prometheus scraping, readiness gauges, and alert rules. Alert delivery and optional Grafana/host dashboards remain to be configured. See [the Docker guide](../infra/docker/README.md).

## References

- [Django deployment checklist](https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/)
- [django-otp authentication](https://django-otp-official.readthedocs.io/en/stable/auth.html)
- [django-otp device extension and throttling](https://django-otp-official.readthedocs.io/en/stable/extend.html)
