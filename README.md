# Fray

Private time tracking for iOS, Android, and responsive web.

## Status

Implementation is starting. This repository currently contains the supplied product blueprint; it is not yet deployable.

See [the product blueprint](docs/product-blueprint.md) for requirements. The application will preserve the supplied purple-and-white mockups and include mandatory MFA, personal time tracking, project collaboration with private entries, and CSV/XLSX/PDF reporting.

Delivery requires reproducible setup, migrations, seed data, environment examples without secrets, passing relevant checks, and independent validation. Deployment instructions will be added alongside implementation. Store publishing and paid infrastructure require their own access and approvals.

## Web milestone implementation branch

The additive web foundation is on `feat/blu-4-web`. See
[web setup and current limitations](docs/web-setup.md) for Docker Compose,
email verification/MFA, tracking, persistence and checks. Collaboration policy
is pending; this branch is not yet the completed shared-project milestone.
