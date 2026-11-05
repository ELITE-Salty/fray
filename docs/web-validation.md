# Engineering checks — web foundation

This is an interim foundation handoff, not acceptance of the whole web milestone.
Exact project visibility/invitation policy remains pending on the BLU-4 human
question card. Invitations, sharing and permitted member/project totals still
need implementation and independent QA after that answer. No mobile delivery is
claimed. Existing repository files were preserved, with an additive README note.

## Recorded checks (5 November 2026)

- Managed GitHub connection/broker: repository metadata read, clone, branch push,
  and draft PR creation succeeded. Baseline commit: `8a2a7e1`.
- Django checks, migration drift check and static collection passed.
- PostgreSQL 17: **22/22 tests passed**; concurrency check is included.
- SQLite local fallback: **21 passed, 1 PostgreSQL-only check skipped**.
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

## Explicit remaining gates and limitations

- Requester decides member-total visibility and invitation authority/delivery.
  The app currently permits only owned projects; membership rows alone grant no
  shared access. This avoids shipping a guessed authorization policy.
- Implement invitations and collaboration, then demonstrate two accounts sharing
  one project and seeing the approved totals. Those checks are not claimed here.
- Independent QA and user web milestone review remain outstanding.
- Broad blueprint features (PDF/XLSX, week/day time-block views, favorites,
  ownership transfer, data erasure workflows, mobile apps and deployment) are
  outside this foundation. Project entries/notes remain personal.
- Local console email is for development; actual email delivery requires SMTP.
- Restart persistence is checked; production backup restore drills and service
  hardening are still release tasks. Keep the stable secret key separately.

Setup and operational behavior are in [web-setup.md](web-setup.md). Source is
[the draft PR](https://github.com/ELITE-Salty/fray/pull/1) on `feat/blu-4-web`.
