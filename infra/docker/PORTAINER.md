# Deploy Fray with Portainer and the Gitea registry

This stack targets **Docker Standalone on Linux amd64/x86_64**. It is not a Swarm stack. The app's public origin is **https://frayapi.klanija.com**, through your existing Cloudflare Tunnel.

## Images

| Image pulled from `gitea.klanija.com/elitesalty/` | Purpose |
|---|---|
| `fray-api` | Django API and the one-shot database migration |
| `fray-web` | Compiled Flutter web app and Nginx API proxy |
| `fray-db` | PostgreSQL 17 plus the least-privilege app-role initialization |
| `fray-monitoring` | Prometheus with Fray scrape configuration and alert rules |

Redis uses `redis:7-alpine` from Docker Hub. Custom images contain application/configuration files, **no account passwords, database data, deployment secrets, or registry credentials**. PostgreSQL and Prometheus persist data in named volumes. No source checkout or host configuration mounts are needed in Portainer.

Each publication has a Git revision tag and a moving `release` tag. Prefer the revision tag in the environment file so all four images stay on the same version. Publishing images does not deploy or change your running server.

## 1. Register your registry in Portainer

In Portainer's **Registries**, add a **Custom registry** with URL `gitea.klanija.com`. Enable authentication if your Gitea packages are private; use your Gitea username and a token with permission to read the packages. Give the target environment access to that registry. Keep these credentials in Portainer, not in the stack YAML.

Publishing uses the direct HTTP endpoint `10.6.2.49:3000` to avoid Cloudflare upload limits. Deployment pulls the same stored images through `gitea.klanija.com` over HTTPS, so the Portainer host does not need an insecure-registry setting or a Docker restart. Only the development machine that pushes directly needs private-network access and its existing HTTP-registry configuration.

`FRAY_REGISTRY=gitea.klanija.com/elitesalty` controls the pull address in the stack. `FRAY_PUSH_REGISTRY` separately controls the publishing script and defaults to `10.6.2.49:3000/elitesalty`. No rebuilding or copying images between registries is required: both addresses serve the same Gitea registry.

If you already pasted the earlier stack, set `FRAY_REGISTRY` to `gitea.klanija.com/elitesalty` in its environment variables and redeploy. Keep your existing `FRAY_IMAGE_TAG` and secrets.

## 2. Create the stack

Create a private environment file once from the repository root:

```sh
python3 infra/docker/configure.py --image-tag release --output .env.portainer
```

Use the supplied private environment file instead if one was generated for this release. The generator refuses to overwrite files. Keep this file and its keys in your private backups. Do not regenerate keys when updating an existing deployment. For a fixed release, set `FRAY_IMAGE_TAG` to the published Git revision tag instead of `release`.

In Portainer:

1. Select the Docker Standalone environment, then **Stacks → Add stack**.
2. Name it **fray** and select **Web editor**.
3. Paste the entire contents of [`portainer.stack.yaml`](portainer.stack.yaml).
4. Under **Environment variables**, choose **Load variables from .env file** and select the generated private environment file. These variables populate the YAML substitutions; no `env_file` mount is needed.
5. Deploy the stack. If your version offers registry selection, use the registry configured above.

Expected services: `db`, `redis`, `api`, and `web` become healthy; `prometheus` runs; `migrate` exits successfully with code **0**. The API waits for migrations. A migration failure must be resolved before exposing the app; inspect its logs in Portainer.

Defaults bind web to host **127.0.0.1:8090** and metrics to **127.0.0.1:9090**. Neither is publicly exposed. Change the port variables before deployment if those host ports are occupied. Do not remove the `127.0.0.1` binding to make phone testing work: phones connect through the HTTPS tunnel.

## 3. Connect Cloudflare Tunnel

Create a published application route for **frayapi.klanija.com**, without a path filter:

| Where your existing connector runs | Service URL |
|---|---|
| Directly on the server | `http://127.0.0.1:8090` |
| In Docker, joined to `fray-edge` | `http://fray-web:8080` |

For a Docker connector, run on the Docker host after the Fray stack is deployed:

```sh
docker network connect fray-edge YOUR_EXISTING_CLOUDFLARED_CONTAINER
```

Also persist this network in the connector's own stack so recreation keeps the connection. Merge with its existing networks:

```yaml
services:
  cloudflared:
    # Keep the existing image, command, tunnel token, and other settings.
    networks: [default, fray-edge]
networks:
  fray-edge:
    external: true
    name: fray-edge
```

Do not put a browser-only Cloudflare Access challenge in front of `/api/*`; the Android client uses Fray's own password/MFA authentication. Enable HTTPS redirects and bypass caching for `/api/*`. Keep the existing tunnel token private. Check:

```sh
curl -fsS https://frayapi.klanija.com/api/health
```

Expected JSON: `{"status":"ok"}` (spacing may differ). Open the hostname in a browser and verify its certificate. The root URL serves the web app; native clients use the same origin's API routes.

## 4. Create your real account

In Portainer, open the running **api** container, select **Console**, connect using `/bin/sh`, then run:

```sh
python manage.py create_fray_user you@example.com --name YourName
```

The command asks for a password and displays the authenticator secret and recovery codes. Add the secret to your authenticator as a six-digit, 30-second TOTP account. Save recovery codes privately. There is no default password or public signup yet.

Optional demo records for this real account:

```sh
python manage.py seed_demo you@example.com
```

The app's **Explore the demo** option is separate in-memory data and does not verify the server connection. To test persistence, sign in to your real account, create an entry, close/reopen the app, and confirm it is still there. Check the same account in the browser too.

## 5. Install on your phone or run in the emulator

The Android app already targets **https://frayapi.klanija.com**. No private registry address belongs in the app. Your phone only needs Internet access to the tunnel.

For a typical modern Android phone, use **`app-arm64-v8a-debug.apk`**. Copy it to the phone, open it, and allow installation from that file/browser app when Android prompts. This is a development build signed with the local Android debug key, suitable for personal testing. It is not a Play Store release. Do not uninstall an existing app merely to resolve a signing conflict without first checking its data; updates must use the same signing key.

Build the split development APKs from source:

```sh
cd apps/fray
flutter build apk --debug --split-per-abi --dart-define=FRAY_API_URL=https://frayapi.klanija.com
```

Outputs are in `apps/fray/build/app/outputs/flutter-apk/`. `arm64-v8a` is for most modern phones, `armeabi-v7a` for older 32-bit ARM phones, and `x86_64` for the usual Android emulator. If unsure, use the larger universal `app-debug.apk` produced by `flutter build apk --debug` without `--split-per-abi`.

For Android Studio, open `apps/fray`, select the emulator, and run `lib/main.dart`. Do a full stop/rebuild after updating native plugins. From a terminal:

```sh
flutter run -d YOUR_DEVICE_ID
```

Real mobile login through your tunnel must be checked after remote deployment. Local automated checks cannot verify your public DNS, connector, certificate, or phone network.

## Updates, monitoring, and backups

To publish a new version from your development checkout after committing changes:

```sh
docker login 10.6.2.49:3000
sh scripts/publish-images.sh
```

This builds all four amd64 images, pushes the Git revision tags, then updates `release`. It uses existing Docker credentials and refuses a dirty source tree. The equivalent individual build is:

```sh
docker build --platform linux/amd64 -f infra/docker/Dockerfile.api -t 10.6.2.49:3000/elitesalty/fray-api:release .
docker push 10.6.2.49:3000/elitesalty/fray-api:release
```

For deployment, back up first. In the stack editor change `FRAY_IMAGE_TAG` to the new published revision, then update/redeploy and pull the new images. Keep the same secrets and stack name. Verify the new `migrate` container exits 0, the app is healthy, and real login still works. Do not delete volumes. Database schema changes may prevent simple rollback to an older image.

View logs in Portainer's service containers. To access Prometheus from your laptop:

```sh
ssh -L 9090:127.0.0.1:9090 your-server
```

Open `http://localhost:9090`; check Targets and `fray_dependency_ready`. Alerts are evaluated, but external notification delivery is not configured. An existing Grafana can query Prometheus through a deliberately configured private connection.

For scripted backups, keep a private copy of `portainer.stack.yaml`, your exact environment file named `.env`, and the existing `backup.sh`/`restore-check.sh` on the Docker host. From that directory:

```sh
COMPOSE_FILE=portainer.stack.yaml COMPOSE_PROJECT_NAME=fray sh backup.sh /srv/private-backups/fray
COMPOSE_FILE=portainer.stack.yaml COMPOSE_PROJECT_NAME=fray sh restore-check.sh /srv/private-backups/fray/fray-TIMESTAMP-SUFFIX/database.dump
```

These names must match the Portainer stack. Backups contain unencrypted private data and secrets; use your encrypted off-machine backup storage. The restore drill uses a separate temporary database. See [the full operations guide](README.md) for retention, session cleanup, and limitations.

References: [Portainer stack creation/environment import](https://docs.portainer.io/user/docker/stacks/add), [Portainer registry access](https://docs.portainer.io/user/docker/host/registries), [Gitea container registry](https://docs.gitea.com/usage/packages/container/).
