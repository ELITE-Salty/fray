# Fray Flutter client

See the [repository README](../../README.md) for local setup, authentication, tests, current limitations, and the future faculty deployment plan.

Quick UI preview:

```sh
flutter pub get
flutter run -d chrome --dart-define=FRAY_DEMO=true
```

This is an in-memory demo, not a real account. The full local launcher serves the compiled client and API on one origin. Native builds default to `https://frayapi.klanija.com` and can override it with `--dart-define=FRAY_API_URL=https://your-host`. See [Docker + Cloudflare deployment](../../infra/docker/README.md) for hosting and phone setup. Stop and rebuild after pulling changes that introduce native plugins; hot reload alone cannot install them.
