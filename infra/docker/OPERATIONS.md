# Monitoring, backups and upgrading

## Upgrade this existing Portainer deployment

Back up the database and existing environment first. Use the updated `portainer.stack.yaml`, not just a new tag: the stack now has a Grafana service and persistent volume. Preserve all existing database/MFA/signing/Redis secrets, domain, network and your HTTP port **8130**. Do not run `configure.py` over an existing deployment.

Add `FRAY_GRAFANA_PASSWORD` as a strong unique password. A locally generated value has also been appended to the ignored `.artifacts/fray-portainer.env` for this workstation's deployment handoff; that file must remain private. For a fresh installation, `configure.py` generates it with the other secrets. Set `FRAY_IMAGE_TAG` to the newly published commit tag for **all five** images: api, web, db, monitoring, grafana.

The database migrations add goals, templates, revision/idempotency metadata and sharing tables. Existing users and time entries are preserved. The one-shot `migrate` service must exit 0 before the API becomes healthy. Keep volumes when updating. Pull images from `gitea.klanija.com/elitesalty`; uploads use the private HTTP registry to avoid the Cloudflare upload limit.

## Grafana

Grafana listens on host loopback `127.0.0.1:3001` by default (`FRAY_GRAFANA_PORT`). Access it from your laptop:

```sh
ssh -L 3001:127.0.0.1:3001 your-server
```

Open `http://localhost:3001`, sign in as `admin` (`FRAY_GRAFANA_USER`) using `FRAY_GRAFANA_PASSWORD`, and open **Dashboards → Fray → Fray operations**. The password environment variable initializes a new Grafana database; changing it later does not rotate an existing administrator password. Change it in Grafana or through its admin CLI.

The provisioned dashboard has API reachability, database/cache readiness, request rate, p95 latency, server-error ratio, email outcomes, throttling and Prometheus alerts. Five Grafana rules evaluate availability, dependencies, errors, latency and mail failures. File-provisioned rules/dashboards are maintained in Git. The Prometheus data source is provisioned automatically. Host disk/CPU monitoring and external synthetic uptime checks are separate future additions; this stack cannot notify if the entire host/network is down.

For optional HTTPS access through your existing connector, add a **separate hostname you control** pointing at `http://fray-grafana:3000` on `fray-edge`. Set `FRAY_GRAFANA_URL=https://that-hostname` and `FRAY_GRAFANA_COOKIE_SECURE=true`, then recreate Grafana. Cloudflare Access can protect this operator-only hostname. Keep `frayapi.klanija.com` pointing at `http://fray-web:8080`.

### Email alerts

Leave `FRAY_ALERT_EMAIL_TO` blank to keep outbound alert mail disabled. To enable it, set:

```dotenv
FRAY_ALERT_EMAIL_TO=your-real-operator-inbox@example.org
FRAY_ALERT_EMAIL_FROM=noreply@klanija.com
```

Grafana reuses `FRAY_EMAIL_HOST`, `FRAY_EMAIL_PORT`, `FRAY_EMAIL_USER` and `FRAY_EMAIL_PASSWORD`. These are Mailjet SMTP credentials, not your mailbox password. This Grafana configuration uses mandatory STARTTLS on port 587 and a verified bare sender address. The API's `FRAY_EMAIL_FROM` can separately use `Fray <noreply@klanija.com>`.

Recreate Grafana. A **Fray email** contact point and notification policy are provisioned when a recipient is present. In **Alerting → Contact points**, send a test notification and check the real inbox. Rules alone do not prove delivery. Notification messages contain service metrics, not entry notes or account data. An owner-supplied recipient is required; no real alert email was sent during implementation validation.

Prometheus stores 15 days of metrics. Grafana's volume stores its users/preferences and alert state. Operational dashboards and rules are reconstructible from the image. Docker JSON logs rotate at three 10 MB files per service.

## Portainer-compatible backups

Run these tools on the **Docker host** from a private checkout. Export your actual Portainer environment to a protected file, including the original MFA/signing/database secrets. Do not replace it with newly generated values. Use the actual stack/project name:

```sh
export FRAY_COMPOSE_FILE=/srv/fray/infra/docker/portainer.stack.yaml
export FRAY_COMPOSE_ENV=/srv/private/fray.env
export FRAY_COMPOSE_PROJECT=fray
sh /srv/fray/infra/docker/backup.sh /srv/private-backups/fray
sh /srv/fray/infra/docker/restore-check.sh /srv/private-backups/fray/fray-TIMESTAMP-SUFFIX/database.dump
```

For a source-built local Compose deployment, the defaults are `infra/docker/compose.yaml`, `infra/docker/.env` and project `fray`. Override paths must be absolute.

Backups contain a custom-format PostgreSQL dump, environment file, Compose recipe, image metadata and SHA-256 checksums. The directory is mode 0700 and files follow umask 077. The files are not encrypted by these scripts: encrypt off-host copies with your backup system and configure retention there. All account records, MFA seeds, templates, goals, sharing memberships/invitations and offline receipts are in PostgreSQL. Local-only pending phone entries are not server backups. Grafana's mutable users/preferences and Prometheus history are not in the application backup; snapshot their volumes separately if needed.

The restore drill creates a uniquely named temporary database on the existing database service, restores the dump with stop-on-error, reads it through Django, decrypts all MFA seeds using the configured key, and removes the temporary database. It never redirects or replaces the live application's database. Run it after upgrades and periodically. A real disaster-recovery drill still requires a separate host and login validation before redirecting the tunnel.

Schedule backups with your host's existing scheduler; for example a private script exporting the three variables above and running `backup.sh` nightly. Monitor its exit code and copy encrypted backups off-host. Also schedule:

```sh
docker compose --project-name fray --env-file /srv/private/fray.env -f /srv/fray/infra/docker/portainer.stack.yaml exec -T api python manage.py clearsessions
docker compose --project-name fray --env-file /srv/private/fray.env -f /srv/fray/infra/docker/portainer.stack.yaml exec -T api python manage.py clear_auth_challenges
```

No host scheduler or VM provisioning is installed by this repository in this milestone.
