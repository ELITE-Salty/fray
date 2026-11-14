# Validation record — 14 November 2026

This records local application and Docker deployment checks. It is not evidence of deployment on the remote server, public Cloudflare TLS, VM provisioning, or a production security audit.

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
| Django tests | 16 passed with SQLite; all 16 also passed with PostgreSQL/Redis |
| Django migration drift | No changes detected |
| Python syntax compilation | Passed |
| Flutter static analysis | No issues found |
| Flutter unit/widget tests | 15 passed |
| Flutter release web build | Passed, renderer and Roboto fonts bundled locally |
| Android development APK | Built successfully with the hosted API URL |
| Android device smoke test | Passed: native timezone detection, secure-storage write/read/delete, date and time dialogs |
| Docker build/startup | API and web images built; migrations completed; API, web, database and cache healthy |
| Database privilege check | App role has no superuser, create-database, or create-role privileges |
| Configuration checks | Nginx configuration and Prometheus configuration/four alert rules passed |
| Monitoring | Loopback Prometheus endpoint reachable; database/cache readiness metrics both 1 |
| Production settings | Health returned 200 through Nginx; secure headers present; Django deployment check has only the two documented HSTS policy warnings |
| Browser demo | Desktop/mobile navigation and CSV download passed |
| Browser real account | MFA recovery-code login, project creation, entry save, persistence after reload, and logout passed; temporary account removed |
| Screenshots | Captured from actual Flutter web UI with synthetic demo data |
| Backup restore | Dump restored into a separate temporary database with 1 fixture account and 12 entries; temporary database and source fixture account removed |
| Portainer stack YAML | Validated with Docker Compose and fresh isolated volumes; bundled PostgreSQL initialization and Prometheus configuration passed; no host bind mounts needed |
| Split Android APKs | ARM64, ARMv7 and x86_64 development APKs built successfully |

Backend coverage includes mandatory MFA, encrypted seeds, TOTP replay, recovery-code consumption, throttling, CSRF, cross-user isolation, invalid durations, overnight intervals, DST elapsed time, overlaps, archived reports, CSV formula escaping, database constraints, and health failures.

Flutter tests cover navigation at 390px and 1440px, duration-only entries, Slovenian date selection, 12/24-hour settings, preserving a saved entry's timezone when travelling, missing/repeated DST times, and cookie persistence, expiry, origin isolation and logout. The device smoke test additionally checks the actual Android plugins; it does not sign in to the remote API.

The browser check lives in `scripts/browser-check.mjs`. It can use separately installed Playwright via `FRAY_PLAYWRIGHT_PATH`. The Docker run used `FRAY_DOCKER_PROJECT=fray-validation`, `FRAY_BROWSER_AUTH=1`, `FRAY_BROWSER_URL=https://frayapi.klanija.com`, and `FRAY_PROXY_ORIGIN=http://127.0.0.1:18090`. Playwright intercepted that HTTPS origin and forwarded requests to local Nginx, exercising production CSRF and Secure-cookie behavior without contacting the public hostname. It is not a real certificate/tunnel test.

Repeat the Android smoke test on a connected emulator with:

```sh
cd apps/fray
flutter test integration_test/mobile_smoke_test.dart -d YOUR_DEVICE_ID
flutter build apk --debug --dart-define=FRAY_API_URL=https://frayapi.klanija.com
```

The final build restores the normal app APK after the integration-test target.

The Portainer stack was exercised using Compose on the local Docker engine, including API readiness, restricted database-role privileges, configuration checks, and monitoring scrape results. This does not claim an actual deployment through the user's remote Portainer UI.

## Not tested / not implemented yet

- Vagrant, cloud-init, fresh Ubuntu installation, deployment speed, public DNS/TLS, or service reboot behavior.
- Concurrent-request stress testing under PostgreSQL row locking; sequential integration tests do not prove all race conditions.
- Physical Android devices, real mobile login through Cloudflare, iOS simulator/device, release signing, or store publishing.
- Load testing, exhaustive accessibility review, full disaster recovery on a second host, Grafana dashboards, or alert notification delivery.
- Collaboration, self-service onboarding/recovery, XLSX/PDF export, or account deletion.

Repeat the commands in the repository README after changes. Keep future deployment evidence separate from these local application screenshots.
