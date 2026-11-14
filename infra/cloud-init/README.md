# Cloud-init — future implementation

Reserved for the faculty deployment milestone. **There is no runnable cloud-config or cloud VM setup yet.**

The planned configuration installs OS packages, downloads a checksum-verified Fray release, writes service configuration at the appropriate cloud-init stage, and invokes the same shared installer as Vagrant. It must keep secrets out of user-data and boot logs and verify HTTPS, service health, and reboot persistence.

See [the faculty deployment plan](../../docs/faculty-project.md), including module-ordering requirements. Develop and try the app today using the [local launcher](../../README.md#try-it-locally).
