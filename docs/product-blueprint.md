# FRAY — Product & Implementation Blueprint

Version: 1.0 | November 2026

> Implementation update (14 November 2026): the chosen client is Flutter and the API is Django. The original blueprint below remains the product roadmap; it is not a claim that every feature is implemented. See [the current scope](../README.md) and [architecture decisions](architecture.md). Vagrant/cloud-init are future work, per the latest project direction.

## 1. Product vision
Fray is a clean, mobile-first time-tracking application for iOS, Android, and the web. Individuals track recurring activities and short- or long-lived projects; collaborators can be invited to shared projects while keeping personal time records private by default.

## 2. Design direction
- Minimalist, light interface; white backgrounds, soft lavender surfaces, deep purple primary actions, rounded cards and inputs, subtle shadows.
- Color-coded calendar entries, with consistent colors per activity/project.
- Mobile navigation: Calendar, Entries, Projects, Reports, Profile.
- Responsive web layout: left navigation rail, calendar workspace, details pane.
- Accessible contrast, large tap targets, clear loading/empty/error states, dark mode optional later.
- Preserve the overall appearance of the approved Fray mockups.

## 3. Core user journeys
### Registration and login
- Email/password registration, verification, password reset, session management.
- Mandatory multi-factor authentication (MFA) enrollment and challenge; prefer TOTP authenticator app and optionally passkeys/WebAuthn. Provide single-use recovery codes.
- Secure reauthentication for changing MFA, email, password, or deleting account.

### Organize work
- Two distinct item types:
  - **Activities:** recurring categories such as Reception, Birthdays, Office Work.
  - **Projects:** potentially numerous, time-limited or ongoing workspaces that support collaboration.
- Projects and activities support name, description, color, archived status; projects also support members and invitations.
- Search, All/Projects/Activities filters, pinned favorites, Recent items, Active/Archived filters, sorting and pagination/virtualization for large lists.
- Creation flows should be quick; archive old projects rather than cluttering the picker.

### Log time
- Select day and project/activity, optionally enter notes.
- Mode A: start and end times; duration auto-calculated and shown.
- Mode B: duration-only (e.g. 1h 30m); no fabricated start/end timestamps.
- Time entries are editable/deletable by their author.
- Handle overnight intervals, timezone/DST changes, invalid/negative intervals and overlapping entries with clear policies and validation.
- Calendar month/week/day views. Timed entries appear as colored time blocks; duration-only entries appear in a separate 'Unscheduled time' section on that date.
- Quick-add from selected date/time slot; entry form can prefill selected time and default duration of 30 or 60 minutes, editable.

### Collaboration
- Project owner invites collaborators by email; pending invites can be accepted/declined.
- Roles: Owner and Member for MVP; Owner can invite/remove members, rename/archive project; Member can log and edit own entries.
- Shared project members can see project metadata and **project aggregate time**; visibility of other people's individual entries/notes should be configurable, default private.
- Personal activities and unrelated projects remain invisible to other users.
- Define ownership transfer and behavior after member removal; retain historical records under a documented policy.
- Invitation expiration, resend/revoke, and duplicate invitation handling.

### Reports and exports
- Month selector, per-project/activity totals, overall total, optional per-day and per-member views (permission-aware).
- Export CSV, XLSX and PDF.
- PDF option 1: compact monthly summary (one row per item, total duration).
- PDF option 2: detailed report (daily entries with date, project/activity, start/end if available, duration, notes if explicitly included).
- Duration-only entries display '—' in start/end columns, not invented times.
- Exports must respect the same authorization and privacy rules as on-screen reports.

## 4. Screens
1. Welcome / Sign up / Login / Password reset
2. MFA enrollment, MFA challenge, recovery codes
3. Calendar (month/week/day), selected-day list and quick add
4. Time entry editor: Time range | Duration toggle, item picker, notes, Save
5. Projects & Activities: search, tabs, favorites, archived, creation
6. Project detail: overview, personal time, aggregate time, members, invitations, settings
7. Invite member: email, role, status
8. Reports: month, totals, filters, exports
9. Profile & Settings: timezone, security, MFA, account management

## 5. Suggested technology stack
- **Client:** React Native + Expo + TypeScript; Expo Router and React Native Web for iOS, Android and responsive web.
- **Backend:** TypeScript with NestJS or Fastify; REST API with OpenAPI specification. Backend framework can change if warranted.
- **Database:** PostgreSQL, with migrations via Prisma or Drizzle.
- **Auth:** a vetted authentication solution supporting MFA, secure refresh/session handling and WebAuthn/TOTP; avoid inventing cryptographic authentication flows.
- **Infrastructure:** managed PostgreSQL, secure secret management, CI/CD, staging and production environments.
- **Exports:** server-side PDF and spreadsheet generation with permission checks.

## 6. Proposed relational data model
- `users` (id, email unique, display_name, timezone, created_at)
- `auth_identities` / auth-provider-managed tables for credentials, sessions, MFA factors, recovery codes
- `activities` (id, owner_user_id, name, description, color, pinned, archived_at)
- `projects` (id, owner_user_id, name, description, color, archived_at, created_at)
- `project_members` (project_id, user_id, role, joined_at; unique project_id+user_id)
- `project_invitations` (id, project_id, invited_email, role, token_hash, expires_at, accepted_at, revoked_at)
- `time_entries` (id, author_user_id, activity_id nullable, project_id nullable, local_date, entry_mode, started_at nullable, ended_at nullable, duration_minutes, notes, created_at, updated_at)
- `audit_events` (id, actor_user_id, action, entity_type, entity_id, occurred_at)

Constraints: exactly one of activity_id/project_id; duration > 0; `entry_mode` determines timestamp nullability; owner/member authorization enforced server-side. Use UUID identifiers and appropriate foreign keys, indexes and check constraints. For timed entries, store UTC timestamps plus the user's IANA timezone; for duration-only entries, store local date and duration.

## 7. API outline
- `POST /auth/...` and MFA endpoints (or auth provider equivalent)
- `GET/POST/PATCH /activities`, `POST /activities/:id/archive`
- `GET/POST/PATCH /projects`, `POST /projects/:id/archive`
- `GET /projects/:id/members`, `POST /projects/:id/invitations`
- `POST /invitations/:token/accept`, `POST /invitations/:token/decline`
- `GET/POST/PATCH/DELETE /time-entries`
- `GET /reports/monthly?month=YYYY-MM`
- `GET /reports/export?month=YYYY-MM&format=pdf|csv|xlsx&detail=summary|detailed`

All endpoints must validate inputs and enforce object-level access control, including filters and exports. Use cursor pagination for large project and entry lists.

## 8. Security and privacy requirements
- MFA required; rate limiting, account lockout safeguards, secure recovery, verified email.
- HTTPS, secure token/session storage, short-lived access tokens where applicable, refresh rotation/revocation.
- Hash passwords with Argon2id if self-managed; never store MFA secrets or invite tokens in plaintext.
- Strict project membership checks; no cross-user access to personal activities or private time-entry notes.
- Least-privilege database roles, backups and restore testing, audit trail for sensitive actions.
- GDPR-ready workflows: export/delete personal data, retention rules, privacy policy, data processing considerations.
- Do not assume that being on a project grants access to another member's personal detailed entries.

## 9. Reporting rules and sample
Example month summary:

| Project / Activity | Total |
|---|---:|
| Website redesign | 14h 30m |
| Marketing campaign | 8h 00m |
| Reception | 20h 00m |
| Birthdays | 3h 00m |
| Office work | 6h 30m |
| **Total** | **52h 00m** |

Detailed PDF columns: Date | Project/Activity | Start | End | Duration | Notes. Notes can be long; wrap text, paginate properly and include page numbers and report period. Offer 'Include notes' checkbox. A shared project report must indicate whether it covers My time or Team totals.

## 10. Implementation phases
**Phase 1 — Foundation:** monorepo, Expo app, backend, PostgreSQL, schema/migrations, CI, environment configuration, auth and mandatory MFA.

**Phase 2 — Personal tracking:** activities/projects CRUD, search/filter/pin/archive, entry modes, calendar, editing, personal reports.

**Phase 3 — Collaboration:** invitations, membership/roles, permission-aware project aggregates, privacy and membership lifecycle.

**Phase 4 — Export and polish:** CSV/XLSX/PDF, responsive web, accessibility, empty/error states, localization/timezone handling.

**Phase 5 — Release:** integration/e2e tests, security review, monitoring, backups, store assets, Apple App Store and Google Play distribution, web hosting.

## 11. Acceptance criteria
- A new user cannot access personal data before authentication and MFA.
- Users can log timed and duration-only entries and see both accurately in calendar and reports.
- A user with 100+ projects can quickly find recent, pinned or searched items.
- An owner can invite another user, who can accept and log time on the shared project.
- Project membership never exposes unrelated activities or projects.
- Reports correctly sum durations and export to CSV, XLSX and both PDF formats.
- Permission checks prevent reading/updating other users' private entries via guessed IDs.
- Core flows work on Android, iOS and responsive web.

## 12. Open decisions for implementation
- Whether MFA is mandatory for every user from launch (assumed yes).
- Whether team members may opt in to sharing detailed entries/notes (default no).
- Whether members can create invitations (MVP: owner only).
- Whether overlaps are allowed with warnings or rejected.
- Whether timers/live tracking are needed (not required for MVP).
- Launch languages: English, Slovenian and Croatian. Appearance: Light, Dark and System.

## 13. Prompt for a coding agent
> Build Fray according to this specification, keeping the approved minimalist purple-and-white design. Start by proposing the monorepo structure, database schema, authentication/MFA approach, and API contract. Explicitly document assumptions and permission boundaries. Implement in small testable milestones, with migrations, automated tests, seed data and clear local development instructions. Do not skip security or invent missing product decisions without flagging them.
