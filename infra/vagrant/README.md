# Vagrant — future implementation

Reserved for the faculty deployment milestone. **There is no Vagrantfile or runnable provisioner yet.**

The planned implementation boots Ubuntu, transfers a prebuilt Fray release, and invokes a shared package-manager-based installer for Nginx, the Django API, PostgreSQL, Redis, and monitoring. It will include trusted local HTTPS and explicit health/reboot/rerun checks.

See [the faculty deployment plan](../../docs/faculty-project.md). Develop and try the app today using the [local launcher](../../README.md#try-it-locally).
