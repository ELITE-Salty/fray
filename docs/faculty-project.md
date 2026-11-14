# Future virtualization assignment

**Planning only.** App development comes first. Neither Vagrant nor cloud-init provisioning/testing is part of this milestone. Their separate folders reserve the required submission structure.

## Proposed stack

| Component | Purpose | Proposed installation |
|---|---|---|
| Nginx | HTTPS termination, static Flutter web assets, API reverse proxy | Ubuntu `apt` |
| Python + Gunicorn + Django | Authenticated application/API, systemd service | `apt` Python/venv, locked packages through `pip` inside a venv |
| PostgreSQL | Persistent application data and sessions | `apt` |
| Redis | Shared session cache and login throttling | `apt` |
| Prometheus | Application/host monitoring and alert rules | `apt` |
| Node exporter | Host CPU, memory, disk metrics | `apt` |
| Certbot | Public certificate issuance and renewal | `apt` |
| Grafana (optional) | Authenticated monitoring dashboards | Signed apt repository |

This gives four functional application components before monitoring is counted. Flutter web is compiled once outside the VM; installing the Flutter SDK on every boot would add time and unnecessary build dependencies. Native Flutter apps will call the same HTTPS API.

Use Ubuntu 24.04 LTS initially, subject to verifying package support when implementation begins. No containers are required for the proposed design. OS services use the standard package manager; application-only Python packages are isolated in a venv. Explain that distinction at the defense.

## Two variants, one installation contract

- `infra/vagrant/`: Vagrantfile, local network/port configuration, source artifact transfer, and provisioner entrypoint.
- `infra/cloud-init/`: cloud-config template, configuration renderer, and artifact download with checksum verification.
- Future `infra/common/`: idempotent setup scripts and service/configuration templates used by both. This prevents divergent security behavior.

Both must start from a clean base image, install the full stack, apply migrations, create an initial account securely, enable services on reboot, and end with health checks. Rerunning provisioning must preserve existing data and secrets. Build a versioned release tarball containing the backend, dependencies lock, and Flutter web assets; do not put repository credentials in user-data or VM logs.

Cloud-init ordering matters: `runcmd` writes a script; `scripts-user` executes it during the final stage. Plan package installation through the package module and use `write_files: defer: true` for files whose owner/path comes from packages. Verify the actual module order on the chosen image before relying on it. See [cloud-init module documentation](https://cloudinit.readthedocs.io/en/latest/reference/modules.html) and [deferred file examples](https://docs.cloud-init.io/en/25.3/reference/yaml_examples/write_files.html).

## Security and operation requirements for that milestone

- Public environment: real DNS, ACME certificate issuance, HTTP-to-HTTPS redirect, and renewal test. Local environment: a locally trusted CA and hostname/IP SANs; manually trust only the public CA certificate on the demonstration machine. A browser warning is not evidence of valid HTTPS.
- Database, Redis, Gunicorn, exporters, and Prometheus listen on loopback/private interfaces. Nginx denies public `/metrics`. Expose only HTTP/HTTPS and restricted SSH. Use SSH keys, firewall rules, and a non-login application user.
- Root-owned environment/secrets files readable only by the service account; unique credentials per installation. Database role has no superuser or database-creation privileges. Do not log initial secrets into cloud-init output.
- Systemd restart policies and hardening; log retention; security updates. Avoid overstating production security until reviewed and tested.
- Dashboards for traffic, 5xx responses, p95 latency, database/cache readiness, CPU/memory, and disk. Add alert routing and test delivery; charts alone do not notify anyone.
- Scheduled PostgreSQL backups, protected MFA/signing keys, encrypted off-machine copies, retention, and a restore drill into a separate database. Keep screenshots free of credentials and private notes.
- Measure fresh deployment time and document resource sizes and availability assumptions. Run PostgreSQL/Redis integration and concurrency tests, service-reboot checks, TLS validation, and provisioning rerun tests for both variants.

## Evidence and submission later

1. Get the team's `XY` and organization year `YY`; create private `devops-fri-YY/sk-XY-virtualization` with the assigned group.
2. Work in small meaningful commits; use the actual app-development history and incremental infrastructure commits. Do not fabricate deployment history.
3. Record fresh `vagrant up` and cloud-init provisioning, final health, HTTPS trust, a service restart, and monitoring.
4. Demonstrate password + MFA login, private time entry creation, report/export, authorization rejection, and backup restore.
5. Write a comprehensive technical README and capture deployment timing, usage screenshots/video, recovery steps, and limitations.
6. Create a compressed source snapshot without `.env`, databases, credentials, `.venv`, SDKs, or private keys. Include reproducible build instructions and lockfiles; submit through Moodle.
7. Every member attends the defense and can explain each submitted component, privilege boundary, cloud-init ordering, TLS issuance/renewal, metrics, and restore process.

Open decisions for that later phase: team/organization IDs, hypervisor/provider, public hostname or local CA, available VM memory/CPU, backup destination, and whether Grafana adds enough value to justify another service.
