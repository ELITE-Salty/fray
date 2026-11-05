# Fray

Private time tracking for iOS, Android, and responsive web.

## Status

Implementation is starting. This repository currently contains the supplied product blueprint; it is not yet deployable.

See [the product blueprint](docs/product-blueprint.md) for requirements. The application will preserve the supplied purple-and-white mockups and include mandatory MFA, personal time tracking, project collaboration with private entries, and CSV/XLSX/PDF reporting.

Delivery requires reproducible setup, migrations, seed data, environment examples without secrets, passing relevant checks, and independent validation. Deployment instructions will be added alongside implementation. Store publishing and paid infrastructure require their own access and approvals.

## Web milestone implementation branch

The responsive web milestone is implemented on `feat/blu-4-web` for independent
QA. See [web setup and current limitations](docs/web-setup.md) for Docker Compose,
email verification/MFA, shared projects, owner email invitations, private tracking,
member totals, persistence and reproducible checks. This updates the original
starting status above. Android/iOS and PDF/XLSX remain later work; production
deployment and independent acceptance are not claimed.
