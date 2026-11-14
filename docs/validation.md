# Validation record — 14 November 2026

This records local application and Docker deployment checks. A separate public check confirmed the original hosted API's HTTPS health endpoint returned 200 after the user's tunnel setup. Local checks of the newer authentication release do not establish its remote deployment or actual Mailjet delivery. This is not evidence of VM provisioning or a production security audit.

## Environment

- Linux host; Flutter 3.47.9 stable, Dart 3.13.7.
- Python 3.14.9 with dependencies pinned in `backend/requirements.txt`.
- SQLite and in-process Django cache for local development/testing; Python 3.12, PostgreSQL 17 and Redis 7 in the Docker deployment.
- Docker Engine 29.9.3, Compose 5.7.1; isolated `fray-validation` project on local ports 18090/19090.
- Headless Chromium; local development server and Docker Nginx origin.
- Pixel 9a Android emulator, x86_64, Android 17/API 37.

## Completed checks

| Check | Result |
|---|---|
| Django tests | 46 passed with SQLite, 2 PostgreSQL-only checks skipped; all 48 passed with PostgreSQL/Redis |
| Django migration drift | No changes detected |
| Python syntax compilation | Passed |
| Flutter static analysis | No issues found |
| Flutter unit/widget tests | 42 passed, including offline restart/retry/conflict cases, PDF generation, Month/Week/Day views and all three languages at phone/desktop widths |
| Flutter release web build | Passed, renderer and Roboto fonts bundled locally |
| Android development APK | Built successfully with the hosted API URL |
| Android device smoke test | Passed: native timezone detection, secure-storage write/read/delete, date and time dialogs |
| Docker build/startup | API and web images built; migrations completed; API, web, database and cache healthy |
| Database privilege check | App role has no superuser, create-database, or create-role privileges |
| Configuration checks | Nginx configuration and Prometheus configuration/five alert rules passed |
| Monitoring | Prometheus reachable; Grafana healthy with eight dashboard panels and five provisioned rules evaluated successfully |
| Production settings | Health returned 200 through Nginx; secure headers present; Django deployment check has only the two documented HSTS policy warnings |
| Browser demo | Desktop/mobile navigation, Week/Day views and CSV/PDF downloads passed |
| Browser real account | Separate password and MFA screens, denial of workspace access before MFA, project creation, entry save, offline reload, persistent running timer, exactly-once reconnect sync and logout passed; temporary account removed |
| Screenshots | Captured from actual Flutter web UI with synthetic demo data |
| Backup restore | Latest drill restored two synthetic accounts, one entry, one membership and one idempotency receipt; Django decrypted the restored MFA seed; temporary database and source fixtures removed |
| Portainer stack YAML | Validated with Docker Compose and fresh isolated volumes; bundled PostgreSQL initialization and Prometheus configuration passed; no host bind mounts needed |
| Split Android APKs | Updated ARM64, ARMv7 and x86_64 development APKs built; ARM64 installed over the existing app on Samsung S25 Ultra and launched successfully |
| Mailjet network | SMTP connection with STARTTLS from the local API container passed; no credentials or real email used |
| Mobile browser signup | Email code from local console mail, MFA enrollment resumed after reload, TOTP confirmation, recovery-code acknowledgement, logout and two-step login passed; synthetic account removed |

Backend coverage includes mandatory MFA, encrypted seeds, TOTP replay, recovery-code consumption, throttling, CSRF, cross-user isolation, invalid durations, overnight intervals, DST elapsed time, overlaps, archived reports, CSV formula escaping, database constraints, and health failures.

Authentication coverage adds email-before-MFA enrollment, no account before both proofs, hashed pending passwords/codes, session binding, expiry, password-change/disabled-user invalidation, bounded attempts, resend cooldown/rotation, unavailable SMTP, disabled signup, duplicate-account races, and concurrent single consumption of a login challenge and recovery code on PostgreSQL. Real-account browser checks use production cookie/CSRF settings through the simulated HTTPS origin.

Flutter tests cover navigation at 390px and 1440px, duration-only entries, Slovenian date selection, 12/24-hour settings, preserving a saved entry's timezone when travelling, missing/repeated DST times, and cookie persistence, expiry, origin isolation and logout. The device smoke test additionally checks the actual Android plugins; it does not sign in to the remote API.

The browser check lives in `scripts/browser-check.mjs`. It can use separately installed Playwright via `FRAY_PLAYWRIGHT_PATH`. The Docker run used `FRAY_DOCKER_PROJECT=fray-validation`, `FRAY_BROWSER_AUTH=1`, `FRAY_BROWSER_URL=https://frayapi.klanija.com`, and `FRAY_PROXY_ORIGIN=http://127.0.0.1:18090`. Playwright intercepted that HTTPS origin and forwarded requests to local Nginx, exercising production CSRF and Secure-cookie behavior without contacting the public hostname. It is not a real certificate/tunnel test.

Run integration tests only on a **disposable emulator**. Flutter may uninstall an existing app automatically after an install failure. In particular, split APKs add ABI offsets to version codes, so an ordinary universal test APK can be treated as a downgrade. Use `adb install -r` for normal phone updates and investigate failures without uninstalling.

Repeat the Android smoke test on a disposable emulator with:

```sh
cd apps/fray
flutter test integration_test/mobile_smoke_test.dart -d YOUR_DISPOSABLE_EMULATOR_ID
flutter build apk --debug --dart-define=FRAY_API_URL=https://frayapi.klanija.com
```

The final build restores the normal app APK after the integration-test target.

The Portainer stack was exercised using Compose on the local Docker engine, including API readiness, restricted database-role privileges, configuration checks, and monitoring scrape results. This does not claim an actual deployment through the user's remote Portainer UI.

`scripts/signup-browser-check.mjs` runs only against a loopback development launcher. Set `FRAY_MAIL_LOG` to the file capturing its console output, `FRAY_BROWSER_URL` to that launcher's URL, and `FRAY_PLAYWRIGHT_PATH` as above. It reads only the synthetic signup message, never sends real email, and removes its fixture account afterward. The [signup screenshot](screenshots/signup-mobile.png) shows the blank form, without credentials. The production-configured browser run used project `fray-auth-validation` and `FRAY_COMPOSE_ENV=.artifacts/docker-validation.env`.

## Not tested / not implemented yet

- Vagrant, cloud-init, fresh Ubuntu installation, deployment speed, or service reboot behavior.
- Broad concurrent-request stress testing under PostgreSQL row locking; the targeted login and offline-write race checks do not prove all race conditions.
- Real mobile signup/login through Cloudflare with Mailjet, iOS simulator/device, release signing, or store publishing. The development APK was installed and launched on the connected Samsung S25 Ultra; this is not an end-to-end hosted authentication test.
- Load testing, exhaustive accessibility review, full disaster recovery on a second host or real alert notification delivery.
- Actual Mailjet credential/sender acceptance and inbox delivery after remote SMTP setup.
- XLSX/full account export and broad real-device file-sharing compatibility. Shared projects, password reset/MFA rotation, PDF export and account deletion now have backend/client regression coverage.

Repeat the commands in the repository README after changes. Keep future deployment evidence separate from these local application screenshots.

## Language and appearance update

Slovenian and Croatian browser contexts verified system-language defaults, dark OS appearance, explicit English/Light selections surviving reload, switching back to their language/Dark, and the translated Profile. Screenshots: [Slovenian settings](screenshots/settings-sl-SI-dark.png), [Croatian settings](screenshots/settings-hr-HR-dark.png), [Slovenian profile](screenshots/profile-sl-SI-dark.png), [Croatian profile](screenshots/profile-hr-HR-dark.png). Backend tests additionally verify localized verification emails and password errors, CSV headings/type labels, and unchanged user content and JSON enum values.

## 0.2.0 feature validation

Account tests cover email+MFA reset, session invalidation, fresh proof for password/recovery/authenticator changes, personal account deletion and shared-owner deletion guards. Shared-project tests cover author-only records, aggregate totals, membership removal, verified-email invitation acceptance and ownership transfer. PostgreSQL concurrent requests confirmed one creation for the same operation UUID and one success/one conflict for the same edit revision.

Offline client tests cover durable writes, failed-write rollback, retained timer/queue across restart, response-loss retries, cross-account isolation, conflicts and removed-project metadata. Real Chromium with WebCrypto storage also survived an API outage and page reload, then synced the queued entry once after reconnect. The timer retained its original start. Temporary browser users were removed.

Grafana was queried through its authenticated API: database healthy, dashboard with eight panels present, all five alert rules reporting `health=ok` without evaluation errors. [Dashboard screenshot](screenshots/grafana-operations.png). The optional email contact point also loaded successfully in a network-isolated disposable container using a synthetic recipient. This is an isolated local stack; no real Mailjet credentials, production inboxes or remote Portainer services were used.

Additional actual UI screenshots: [Week](screenshots/week-desktop.png), [Day](screenshots/day-desktop.png), [offline queue and timer](screenshots/offline-desktop.png). These are synthetic app/operations evidence; VM deployment evidence is deliberately deferred.

### Samsung smoke-test incident

The 0.2.0 device smoke test passed for native timezone detection, secure-storage read/write/delete and date/time pickers. However, its universal APK had version code 2 versus the installed ARM64 APK's 2001. Flutter automatically uninstalled the older app after the downgrade error, resetting local sign-in/preferences. The user was informed; server records were unaffected. The normal ARM64 app (version code 2002) was then restored. Future integration tests should use a disposable emulator; do not run this workflow over a user's installed app.
