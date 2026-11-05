# Engineering checks — web foundation

The requester confirmed all-member totals with private individual entries/notes,
and owner-only email invitations with explicit in-app acceptance. The shared-project
implementation and reproducible two-account browser demonstration are included.
Independent QA and user acceptance remain separate gates. Existing files and records
are preserved; no mobile or production deployment is claimed.

## Recorded checks (5 November 2026)

- Managed GitHub connection/broker: repository metadata read, clone, branch push,
  and draft PR creation succeeded. Baseline commit: `8a2a7e1`.
- Django checks, migration drift check and static collection passed.
- PostgreSQL 17: **28/28 tests passed**; concurrency check is included.
- SQLite local fallback: **27 passed, 1 PostgreSQL-only check skipped**.
- Separate PostgreSQL server stop/start plus a new application process retained
  a uniquely named test record. This is distinct from Compose-volume evidence.
- Docker Compose installation/restart check passed on GitHub Actions at
  [run 42104874604](https://github.com/ELITE-Salty/fray/actions/runs/42104874604)
  for `1df32c6`: built image, migrations, readiness, all PostgreSQL tests,
  migration drift, and record persistence after `db` + `web` restart. The local
  engineering sandbox has no Docker executable.
- Responsive browser smoke and screenshot collection were added subsequently;
  consult the current PR checks for the latest result and downloadable artifacts.

## Test coverage

Authentication tests use real allauth forms for signup/email confirmation,
password/MFA login, mandatory enrollment and reauthentication. They check
unverified-session rejection, wrong OTP rejection, encrypted stored seeds,
single-use TOTP/recovery, failed-password throttling, password-reset email,
POST logout, CSRF and anonymous route protection.

Tracking tests check duration-only timestamp nullability, overnight intervals,
UTC elapsed duration across both DST transitions, rejection of ambiguous and
nonexistent clock times, invalid durations/targets, independent timers,
double-start/stop idempotence, foreign entry/timer/project denial, privacy of
calendar/report/CSV output, archive retention/restoration, timezone selection,
CSV formula escaping, distinct same-name projects and database constraints.
The PostgreSQL concurrency test starts two timers simultaneously for one account
and verifies exactly one start succeeds.

## Collaboration coverage

Tests exercise owner-only sending and archiving, actual Django mail generation,
explicit acceptance, verified email binding, wrong-account denial, seven-day expiry,
duplicate sends/acceptance, retry after SMTP failure, archived-project denial and
CSRF. Two accounts join one project, start independent timers simultaneously, stop
at deterministic 3600/1800 seconds, and both see exact 5400-second project totals and
correct member subtotals. Shared entries/notes remain absent from the other account's
calendar, entries, report, CSV and edit routes. Members can also add manual entries.

The Playwright flow creates a separate project through the UI, sends an invitation,
accepts through a second mobile browser session, adds 40/20-minute entries, starts
both timers independently, stops each, and checks member subtotals and private entry
isolation. Desktop owner and mobile member screenshots are captured. CI performs
clean Compose installation, tests, migrations and restart persistence first.

## Explicit remaining gates and limitations

- Independent QA and user web milestone review remain outstanding. Consult the PR's
  current checks and task delivery document for results tied to the latest commit.
- Broad blueprint features (PDF/XLSX, week/day time-block views, favorites,
  ownership transfer, data erasure workflows, mobile apps and deployment) are
  outside this web milestone. Project entries/notes remain personal.
- Actual outbound email requires the operator's configured SMTP server; CI checks
  email construction, transport failure/retry and in-app acceptance. No third-party
  production mail account has been configured or claimed as verified.
- Restart persistence is checked; production backup restore drills and service
  hardening are still release tasks. Keep the stable secret key separately.

Setup and operational behavior are in [web-setup.md](web-setup.md). Source is
[PR 1](https://github.com/ELITE-Salty/fray/pull/1) on `feat/blu-4-web`.
