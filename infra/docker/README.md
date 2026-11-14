# Fray on your Docker server + Cloudflare Tunnel

This is the self-hosted deployment path for **https://frayapi.klanija.com**. It serves both the Flutter web app at `/` and the API at `/api/`. The Android client uses this HTTPS origin by default. Vagrant/cloud-init remain a separate future faculty milestone.

**Using prebuilt registry images with Portainer? Follow [the Portainer guide](PORTAINER.md) and use `portainer.stack.yaml`.** The source-build instructions below remain available for a server checkout.

The repository contains the deployment files; it does not create a Cloudflare route, push to Gitea, or connect to your remote server automatically.

## Stack and network

```text
Android / browser
       | HTTPS: frayapi.klanija.com
Cloudflare edge (public TLS certificate, HTTPS redirect)
       | encrypted Cloudflare Tunnel
Your existing cloudflared connector
       | HTTP on a private Docker network or host loopback
Nginx :8080 ---- Django/Gunicorn :8000 ---- PostgreSQL :5432
                         |                 (persistent volume)
                         +---- Redis :6379 (sessions/cache + login limits)
                         +---- Prometheus scrapes metrics and readiness
```

Only Nginx is attached to the `fray-edge` network. PostgreSQL, Redis, API, and Prometheus share an internal Docker network. The origin port is published to **127.0.0.1:8090**, not all interfaces. Prometheus is on **127.0.0.1:9090**. API/DB/Redis have no host ports. Never publish the Nginx origin as public HTTP: its HTTPS forwarding header assumes a trusted tunnel.

Prometheus also has its own bridge network so Docker can publish its loopback port; containers attached only to an internal network do not receive published ports on the tested Docker Engine. It does not join the tunnel's edge network.

Nginx serves precompiled Flutter assets. Its image builds Flutter from the official Git repository at a pinned release commit; your server does not need a host Flutter SDK. Python dependencies and Flutter dependencies are locked. Base images follow maintained Python 3.12, PostgreSQL 17, Redis 7, and Nginx stable tags; Prometheus has an explicit version. These tags are not immutable image digests: periodically pull/rebuild, review upstream releases/security updates, and record the deployed image IDs.

The intended server is Linux x86/amd64 with Docker Engine and the Compose plugin. Python 3 is used once to generate configuration. Allow at least 4 GB RAM and several GB of temporary disk space for the first Flutter build; runtime usage is smaller. First builds download the SDK/dependencies; subsequent builds reuse Docker layers.

## 1. Pull your repository and configure the server

Commit the source changes and push them to your Gitea repository using your normal workflow. On the remote server, clone that repository, then:

```sh
cd fray/infra/docker
python3 configure.py --domain frayapi.klanija.com
docker compose up -d --build --wait
docker compose ps -a
```

`configure.py` creates `.env` with independent Django signing/MFA keys, application database credentials, PostgreSQL bootstrap credentials, and Redis credentials. It uses mode `0600` and refuses to overwrite existing secrets. `.env` is ignored by Git and excluded from Docker build contexts. Keep it only on your server and in private encrypted backups. Docker administrators can inspect container environment variables; host/Docker administrator access is trusted.

Change ports on first setup if needed:

```sh
python3 configure.py --domain frayapi.klanija.com --http-port 8090 --metrics-port 9090
```

Do not regenerate credentials when volumes already exist. The PostgreSQL initialization script runs only for a new volume. Password rotation on an existing database requires changing the actual database role password as well as `.env`.

Startup waits for database/cache health, runs migrations as a one-shot service, starts the API, and then starts Nginx and Prometheus. An exited `migrate` container with exit code 0 is expected. Services restart on host reboot when Docker starts. The app runs as an unprivileged user with a read-only root filesystem; Nginx also runs without root privileges. The application database role cannot create databases or roles and is not a superuser.

`python manage.py check --deploy` reports Django warnings W005 and W021: HSTS is enabled for this hostname, but descendant-domain coverage and browser preload are deliberately unset. Enable those only after reviewing every affected hostname and the preload commitment.

Verify the private origin before configuring the tunnel:

```sh
curl -fsS -H 'Host: frayapi.klanija.com' http://127.0.0.1:8090/api/health
```

Expected: `{"status":"ok"}`. Use the public HTTPS URL for real sign-in; production cookies are Secure and CSRF checks use the public origin.

## 2. Point your existing Cloudflare Tunnel at Nginx

Add a published application route with hostname **frayapi.klanija.com**, no path restriction, and the service below. If a DNS record already exists for that hostname, reconcile it with the tunnel route rather than creating conflicting records.

### cloudflared runs directly on the server

Use **HTTP → `localhost:8090`** as the service. The origin leg is host loopback; the tunnel carries traffic encrypted to Cloudflare.

### cloudflared runs in Docker

Attach that existing connector to Fray's edge network:

```sh
docker network connect fray-edge YOUR_CLOUDFLARED_CONTAINER
```

Use **HTTP → `fray-web:8080`** as the service. `localhost` inside cloudflared points to that container, not to Nginx.

Persist this connection in the connector's own Compose file, so it survives recreation:

```yaml
services:
  cloudflared:
    # Keep your existing image, command, token, and existing networks.
    networks:
      - default
      - fray-edge
networks:
  fray-edge:
    external: true
    name: fray-edge
```

Merge that snippet with your existing configuration; do not replace existing connector settings. Fray creates `fray-edge` on first startup. If using another edge-network name, set `FRAY_EDGE_NETWORK` in Fray's `.env` and use that same name in the connector.

In Cloudflare:

- Enable **Always Use HTTPS** for the public hostname/zone.
- Keep automatic caching bypassed for `/api/*`; do not apply a Cache Everything rule to authenticated API responses. API responses also carry `Cache-Control: no-store` at Nginx.
- Fray handles password + MFA itself. A Cloudflare Access browser-login challenge in front of `/api/*` will prevent the native app from signing in unless Access support is added to the client. Do not embed an Access service-token secret in the mobile app.
- Apply sensible per-client login rate limits at Cloudflare if your plan supports them. Redis already applies account-level limits. The origin deliberately does not trust arbitrary client IP headers.

Check the real route:

```sh
curl -fsS https://frayapi.klanija.com/api/health
```

Open **https://frayapi.klanija.com** in a browser. Confirm the certificate is valid and there are no redirect loops. No Cloudflare token or tunnel credential is needed in the Fray repository.

## 3. Create your account

On the server, from `infra/docker`:

```sh
docker compose exec api python manage.py create_fray_user you@example.com --name YourName
```

Enter a strong password when prompted. The command displays the authenticator secret, `otpauth://` URI, and eight recovery codes for initial handoff. Add the secret manually to your authenticator app (six digits, 30-second TOTP), and store recovery codes privately. Do not paste this output into Gitea, logs, screenshots, or chat.

Optional sample data:

```sh
docker compose exec api python manage.py seed_demo you@example.com
```

Public signup, email verification, self-service password reset, and MFA rotation are still planned. The current release supports operator-created accounts with mandatory MFA.

## 4. Run the Android app

Open `apps/fray` in Android Studio and select your Android emulator/device. Stop and run the app again after pulling these changes: timezone and secure-storage plugins require a full rebuild, not just hot reload.

The default native API URL is already `https://frayapi.klanija.com`. The equivalent explicit terminal command is:

```sh
cd apps/fray
flutter run -d YOUR_ANDROID_DEVICE_ID --dart-define=FRAY_API_URL=https://frayapi.klanija.com
```

For a development APK to sideload on your own phone:

```sh
flutter build apk --debug --dart-define=FRAY_API_URL=https://frayapi.klanija.com
```

Output: `apps/fray/build/app/outputs/flutter-apk/app-debug.apk`. This is a development-signed APK, not a Play Store release. Release builds require a proper signing key before distribution; release API configuration rejects HTTP. Native session/CSRF cookies are stored using platform secure storage, scoped to the API origin, and respect the server's eight-hour session expiry. Passwords and MFA codes are not persisted. Logout invalidates the server session and removes its cookie. Android application backup is disabled to avoid copying unusable encrypted session data to another device.

Until the tunnel is configured, the app can still open **Explore the demo**, but real login will need the live API.

## Updates from Gitea

Back up first, then pull and rebuild:

```sh
cd fray/infra/docker
sh backup.sh /srv/private-backups/fray
git pull --ff-only
docker compose pull db redis prometheus
docker compose build --pull api web
docker compose up -d --wait
curl -fsS https://frayapi.klanija.com/api/health
```

The Docker build works from tracked source; it does not require committing local Flutter build output. There is no Git credential in an image. If you later want Gitea Actions to publish images to your registry, the same Dockerfiles can be used without changing the application.

Migrations run when their service/image is recreated. Before rolling back an application release, inspect its migration compatibility; restoring an old image alone cannot undo a destructive schema change. Do not use `docker compose down -v` for normal updates: it deletes persistent volumes.

## Monitoring and logs

```sh
docker compose logs --tail=100 api web
docker compose ps -a
```

Prometheus stores 15 days of metrics. Open it through an SSH tunnel from your laptop:

```sh
ssh -L 9090:127.0.0.1:9090 your-server
```

Then visit `http://localhost:9090`, check **Status → Targets**, and query:

```promql
fray_dependency_ready
sum(rate(fray_http_requests_total[5m]))
sum(rate(fray_http_requests_total{status=~"5.."}[5m]))
histogram_quantile(0.95, sum by (le) (rate(fray_http_request_seconds_bucket[5m])))
process_resident_memory_bytes{job="fray"}
```

Alert rules cover a missing API target, database/cache readiness, error ratio, and latency. They appear in Prometheus; **notification delivery is not configured**. Add Alertmanager and a receiver for email/chat notifications when your preferred channel is known. Grafana is optional; the metrics are ready for an existing Grafana installation. Host CPU/disk monitoring needs a host exporter separately; current process metrics do not claim to cover the entire host.

`/metrics` is blocked at the public Nginx origin. Docker rotates service logs (three 10 MB files per service). Session rows should be pruned daily using a host cron/systemd schedule for:

```sh
docker compose exec -T api python manage.py clearsessions
```

## Backups and restore drills

```sh
sh backup.sh /srv/private-backups/fray
sh restore-check.sh /srv/private-backups/fray/fray-TIMESTAMP-SUFFIX/database.dump
```

The backup directory contains a PostgreSQL custom-format dump, the exact environment/secrets file, image metadata, and checksums. Permissions are private. The dump and secrets are **not encrypted by this script**: copy them to encrypted off-machine backup storage with your normal backup system, and set retention there. Losing the MFA encryption key makes stored authenticator seeds unreadable.

The restore drill creates a separate temporary database, restores the dump, checks user/entry tables, and removes that temporary database. It never replaces the live database. A real disaster recovery should start a separate clean stack with the backed-up environment and restore the dump there before redirecting the tunnel; test login with a backed-up account and its authenticator before cutover.

## Troubleshooting

- **502 at Cloudflare:** check connector network membership and the origin URL from inside the connector's network. A Docker connector must not use host `localhost` for this stack.
- **403 CSRF:** verify the browser uses the exact configured HTTPS hostname, and that `FRAY_DOMAIN` matches. Do not disable CSRF.
- **Login returns HTML:** an Access challenge, tunnel error, or proxy rule is intercepting `/api/*`.
- **Migrations fail:** inspect `docker compose logs migrate db`; keep existing credentials and volumes intact.
- **Redis is full:** the cache fails closed rather than evicting login-limit keys. Inspect memory pressure and increase its memory limit or add application-level bounds as usage grows.
- **Port already allocated:** change `FRAY_HTTP_PORT` / `FRAY_METRICS_PORT` in `.env`; update the host-side tunnel origin if necessary.

References: [Cloudflare published routes](https://developers.cloudflare.com/tunnel/concepts/routing/), [Docker Compose startup ordering](https://docs.docker.com/compose/how-tos/startup-order), [Django deployment checklist](https://docs.djangoproject.com/en/5.2/howto/deployment/checklist/).
