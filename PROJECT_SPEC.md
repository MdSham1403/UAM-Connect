# UAM Connect — Product & Build Specification

**Version:** 1.1 (Phase 0 baseline) · **Date:** 2026-10-12 · **Owner:** Sam (Superadmin and technical owner)
**Status:** Draft pending owner review. Built from the owner's v1.0 product baseline; every change is listed in §0.

Related documents: [PROJECT_STATE](PROJECT_STATE.md) · [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DATABASE](DATABASE.md) · [SECURITY](SECURITY.md) · [TEST_PLAN](TEST_PLAN.md) · [AGENTS](AGENTS.md)

---

## 0. Amendments to v1.0

| # | Change | Reason |
|---|---|---|
| A1 | Added **Superadmin** as an application-level privilege above Admin, provisioned only through a trusted process. | Owner requirement; v1.0 had only Member / Team Lead / Admin. |
| A2 | Phase 0 is **documentation only**. Scaffold, environment files, CI and design system move to the start of Phase 1. | v1.0 Phase 0 included setup work; Phase 0 must not build the app. |
| A3 | Day estimates removed. | No fixed-duration promises. Gates matter, not dates. |
| A4 | Organizational hierarchy is **configurable**; no reporting lines are assumed. | Reporting relationships are unconfirmed. |
| A5 | Schema additions (severity levels, help-request volunteers, rate-limit events, platform owners, team settings, notification preferences). | v1.0 required these behaviours but lacked tables. See [DATABASE](DATABASE.md). |
| A6 | v1.0 "Optional" Team Lead capabilities replaced with proposed defaults (decision D-05). | Optional is not testable. |
| A7 | Acceptance checks given stable IDs; three Superadmin checks added (AC-S8 to AC-S10). | Traceability. |

Unresolved decisions are tracked in the register in [PROJECT_STATE](PROJECT_STATE.md) and referenced here as `D-xx`.

---

## 1. Product definition

**Problem.** UAM operations depend on information spread across Microsoft Teams, WhatsApp groups, ticketing tools and individual knowledge. During outages, staffing gaps and shift changes it is hard to establish the current situation, find the right person and identify the next action.

**Solution.** A private shared workspace showing team availability, role coverage, incidents, help requests and handovers in one place.

**Principles**
- Complement existing tools; do not replace Sapphire, Microsoft Teams or WhatsApp.
- Common actions take a few taps on a phone.
- Operational roles are configurable without source-code changes.
- Ownership and outstanding actions are explicit.
- Internal information is protected by database-enforced permissions.
- Finish the core product before optional features.

**Success.** An authorized member can join, see current coverage, coordinate an incident, request help, read announcements, complete a handover and find approved knowledge notes, and an administrator can safely manage membership and roles.

**Scale.** 15–18 members, one private team, multiple operational roles per member, one or more shifts.

### Target users
| User | Needs |
|---|---|
| UAM Engineer | See coverage, update status, report/join incidents, request help, hand over. |
| Team Lead | Coordinate ownership, publish announcements, publish knowledge. |
| Administrator | Approve members, manage roles/shifts/codes, review audit history. |
| Superadmin (owner) | All of the above plus configuration, diagnostics, deployment and recovery. |
| Senior leadership (VP, Deputy Manager) | Same as any member unless explicitly granted application permissions. |

### Non-goals
- Replacing the ticketing system, Teams or WhatsApp; no chat server.
- Public registration, multi-tenant SaaS, or large-enterprise features.
- Storing passwords, access tokens, private keys, banking credentials or confidential customer data.
- Continuous location tracking or covert activity monitoring.
- A separate Python backend, Redis or AI service (unless a demonstrated requirement justifies one).
- Full offline operation (only a clear offline indicator and safe local drafts).

---

## 2. Technology decisions

| Layer | Selection |
|---|---|
| Frontend | React + TypeScript + Vite |
| Styling | Tailwind CSS, reusable mobile-first components |
| PWA | Web app manifest + service worker |
| Authentication | Supabase Auth |
| Database | Supabase PostgreSQL |
| Real-time | Supabase Realtime |
| Authorization | PostgreSQL Row Level Security (RLS) + privileged database functions |
| Push | Web Push with a trusted server-side sender (D-09) |
| Validation | Zod on the client; database constraints and server-side checks as the authority |
| Testing | Vitest + React Testing Library + Playwright |
| Version control | Git + GitHub |
| Deployment | Approved static frontend hosting + Supabase (D-04) |

Rationale: minimal custom infrastructure; database and realtime in one managed platform. Assumption: Supabase managed services are acceptable for development; free-tier limits must be re-checked before release, and no real banking or company data may enter an unapproved environment (D-11).

---

## 3. Roles and permissions

Three **separate** concepts:
1. **Organizational rank** — Vice President, Deputy Manager, UAM Engineer (profile data; configurable; never grants access).
2. **Operational responsibilities** — BAU/Ticketing, Queue Manager, Onboarding, Resignation, Retain, Reconciliation, plus any role admins add. Many-to-many with members.
3. **Application permissions** — Member, Team Lead, Admin, Superadmin.

A higher organizational rank does not grant application permissions. A Deputy Manager is an ordinary Member until an Admin assigns more.

### Superadmin
- Highest application-level authority, independent of organizational hierarchy.
- Manages membership, application permissions (including Admin), operational roles, configuration, audit history and technical diagnostics; responsible for troubleshooting, deployment and recovery.
- **Never** granted via public signup, a joining code, a profile field, a self-assigned role, or a client-side email comparison.
- Provisioned through a trusted administrative process, documented in [SECURITY](SECURITY.md) §7 (proposed, D-01). Recovery must not depend solely on a UI that could lock out its owner.

### Application access matrix (proposed defaults, D-05/D-06)
| Capability | Member | Team Lead | Admin | Superadmin |
|---|---|---|---|---|
| View team and role coverage | Yes | Yes | Yes | Yes |
| Update own availability | Yes | Yes | Yes | Yes |
| Post help requests and replies | Yes | Yes | Yes | Yes |
| Create and update incidents | Yes | Yes | Yes | Yes |
| Claim an incident / volunteer | Yes* | Yes | Yes | Yes |
| Assign/reassign incident ownership | No | Yes | Yes | Yes |
| Resolve / reopen incidents | No | Yes | Yes | Yes |
| Publish and pin announcements | No | Yes | Yes | Yes |
| Knowledge notes | Draft | Publish | Publish | Publish |
| Approve/reject/suspend members | No | No | Yes | Yes |
| Manage joining codes | No | No | Yes | Yes |
| Manage operational role definitions | No | No | Yes | Yes |
| Grant Member / Team Lead permission | No | No | Yes | Yes |
| Grant / revoke Admin | No | No | No | Yes |
| Configure shifts and team settings | No | No | Yes | Yes |
| View audit log | No | No | Yes | Yes |
| Diagnostics, configuration, recovery | No | No | No | Yes |

\*A claim becomes official under assignment rules; Team Leads and above confirm or reassign.

### Operational role management
Each role has: stable ID, name, optional description, active flag, optional colour/icon, optional "eligible to coordinate" designation, assigned members with optional primary designation, and optional per-shift coverage requirement. Renaming never breaks history. Roles with historical references **cannot be deleted**; deactivate instead.

---

## 4. Screens and navigation

Bottom navigation on mobile; compact sidebar on larger screens. Primary: **Home** (Live Ops Board), **Team**, **Incidents**, **Handover**. Secondary: Help Requests, Announcements, Knowledge, Notifications, Profile/Settings. Admin screens appear only to authorized users (visibility is cosmetic; enforcement is in the database).

| Screen | Required behaviour |
|---|---|
| Welcome / Login | Sign in, password recovery, request membership |
| Join Request | Enter private code, submit profile, show pending/approved/rejected |
| Home / Live Ops Board | Shift summary, coverage gaps, active incidents, help requests, latest announcements |
| Team Directory | Search members; view roles and status |
| Member Profile | Display name, organizational title, role assignments, availability |
| Availability Editor | Status, optional end time and note |
| Shift Management | Shift definitions, time zones, members, role coverage |
| Incident List / Detail | Filter by state, severity, owner; timeline, updates, owner, volunteers |
| Help Requests | Create, target role/person, volunteer, confirm assignment |
| Announcements | Publish, pin, acknowledge, history |
| Handover List / Detail | Current/past handovers, drafts, unresolved items, receiver acknowledgement |
| Knowledge Board | Search, view, draft, edit, publish |
| Notifications | Read/unread, preferences |
| My Profile | Edit permitted fields, status, preferences |
| Admin: Members | Approve/reject requests, suspend, manage codes |
| Admin: Roles | Create, edit, assign, deactivate operational roles |
| Admin: Settings | Code rotation, shifts, notification rules, team configuration |
| Admin: Audit Log | Review sensitive actions |

---

## 5. Core workflows

**A. Joining.** Admin generates a random private code → prospective member redeems it and creates an authenticated account (order: D-03) → submits display name and organizational title → membership is created **pending** → Admin approves or rejects → approval activates membership → Admin assigns operational roles and application permissions separately. The code is never a substitute for authorization: store only a hash, expire, revoke, rate-limit, and always require explicit approval. Public signup can never assign roles or create an Admin.

**B. Availability and shifts.** Statuses: Available, Busy, On Break, Off Shift, with optional note and expiry. Expired or stale status displays **Unknown**, never Available. Configured shifts define expected coverage; manual status is self-reported. The Live Ops Board shows the current shift, expected members, who has checked in, role coverage/gaps, active incidents and help requests. No location tracking.

**C. Incidents.** Any approved member creates an incident (title, affected service, severity, description) → unique reference generated → claim or assignment of owner → timestamped updates and volunteers → active until recovery confirmed → authorized person resolves with a resolution summary. Statuses: Open → Investigating → Monitoring → Resolved; reopening requires a recorded reason. Chronological history of changes and assignments is kept. Severity levels are configurable (defaults: Low, Medium, High, Critical; D-15).

**D. Help requests.** Requester selects needed role or person, description, urgency, optional incident/ticket reference → eligible teammates volunteer → requester or coordinator confirms. Statuses: Open → Claimed → In Progress → Completed, or Cancelled. A claim must never silently overwrite a confirmed assignment; conflicts return a clear response.

**E. Handover.** Outgoing member creates a handover for a shift, adds active incidents, outstanding requests, blockers and follow-ups (each with owner and status) → submits → receiver acknowledges → unresolved items stay visible until resolved or reassigned. Submitting a handover does **not** complete its items.

**F. Announcements and notifications.** Announcement: title, message, category, author, timestamp, optional expiry, optional pin, optional acknowledgement requirement. In-app notifications are persistent with read/unread state. Push is optional, permission-based, and carries only generic text (e.g. "A new UAM incident needs your attention"); details require opening the authenticated app.

**G. Knowledge notes.** Members draft; authorized editors publish. Fields: title, content, category, tags, author, state, timestamps, revision history. Search covers title, tags and content. Notes must be approved for team sharing and must not contain passwords, tokens, keys or confidential customer information.

---

## 6. Data model and security summary

Full detail: [DATABASE](DATABASE.md) (proposed schema) and [SECURITY](SECURITY.md).

- UUID keys, UTC timestamps, foreign keys, constraints, indexes; `team_id` on team-owned rows.
- Stable role IDs, never names. Organizational title is profile data, not an authorization input.
- The server/database, not the browser, is authoritative for approval, ownership and permission changes.
- RLS is mandatory on every protected table; hiding UI is never a control.
- Pending members read only their own request/profile. Suspended members lose protected access; history remains.
- Versioned SQL migrations for every schema change. No secrets in Git or frontend bundles.

---

## 7. Acceptance criteria (release gates)

Marking an item here does not execute a test. Evidence is recorded only in [PROJECT_STATE](PROJECT_STATE.md) and [CHANGELOG](CHANGELOG.md) after the check actually runs. Phase mapping: [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md); test method: [TEST_PLAN](TEST_PLAN.md).

**Membership and roles**
- [ ] AC-M1 A valid joining code creates a pending request, not automatic access.
- [ ] AC-M2 Expired, revoked and invalid codes are rejected; repeated attempts are rate-limited.
- [ ] AC-M3 Only authorized Admins can approve members or grant application permissions.
- [ ] AC-M4 An engineer can hold Queue Manager and Retain simultaneously.
- [ ] AC-M5 A newly created operational role can be assigned without a code change.
- [ ] AC-M6 Suspended members lose protected access while historical records remain intact.

**Live Ops Board and shifts**
- [ ] AC-L1 Members can update and expire their own availability.
- [ ] AC-L2 Expired or stale status becomes Unknown rather than Available.
- [ ] AC-L3 Shift coverage reflects configured assignments and actual confirmations.
- [ ] AC-L4 Coverage gaps and active incidents are visible on mobile.
- [ ] AC-L5 Real-time updates reach authorized connected clients without manual refresh.

**Incidents and help requests**
- [ ] AC-I1 Members can create incidents and share ticket references without duplicating the ticketing system.
- [ ] AC-I2 Incident status, owner, updates and resolution history are retained.
- [ ] AC-I3 Concurrent claims cannot silently overwrite confirmed ownership.
- [ ] AC-I4 Help requests support volunteering, confirmation, completion and cancellation.
- [ ] AC-I5 Unauthorized users cannot resolve or reassign restricted records.

**Announcements and handovers**
- [ ] AC-H1 Authorized users can publish and pin announcements.
- [ ] AC-H2 Acknowledgements are recorded per member and announcement.
- [ ] AC-H3 A submitted handover remains distinct from completion of its items.
- [ ] AC-H4 Unresolved handover items retain their owner and remain discoverable.
- [ ] AC-H5 Expired/archived announcements and old handovers are consistent with retention rules (D-10).

**Notifications and knowledge**
- [ ] AC-N1 In-app notifications support unread/read state.
- [ ] AC-N2 Push delivery works on supported, permission-enabled devices.
- [ ] AC-N3 Denied push permission does not break core functionality.
- [ ] AC-N4 Knowledge drafts are not exposed as published notes.
- [ ] AC-N5 Published notes are searchable and revisions can be reviewed.

**Security, quality and deployment**
- [ ] AC-S1 RLS blocks anonymous, pending and cross-team access.
- [ ] AC-S2 Client-side role tampering does not grant privileges.
- [ ] AC-S3 No server secrets appear in frontend bundles or logs.
- [ ] AC-S4 Install, refresh, sign-out and session expiry work on supported browsers.
- [ ] AC-S5 Core workflows work on narrow mobile screens and desktop.
- [ ] AC-S6 Migrations apply from a fresh environment; backups and recovery are documented.
- [ ] AC-S7 Production build, automated tests and end-to-end smoke tests pass.
- [ ] AC-S8 *(added)* No path (signup, join code, profile edit, client call) can create or promote a Superadmin; bootstrap is documented and verified.
- [ ] AC-S9 *(added)* Owner access can be restored without relying on the application UI (recovery runbook exercised).
- [ ] AC-S10 *(added)* The last Superadmin cannot be removed through application paths.

---

## 8. Performance and reliability targets

Engineering targets to validate, not guarantees:
- Dashboard usable within about 2 seconds on a reasonable connection, excluding slow external dependencies.
- Real-time changes visible within a few seconds under normal conditions.
- Clear loading, empty, error and retry states on every important screen.
- Clear disconnected indicator; safe drafts preserved locally where appropriate.
- Offline behaviour must never bypass authorization or silently overwrite newer server data.

---

## 9. Phases

Details, dependencies and checkpoints: [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md).

| Phase | Scope | Exit gate |
|---|---|---|
| 0 | Documentation, architecture, security plan, acceptance criteria | Owner reviews and commits documents |
| 1 | Scaffold, Supabase setup, auth, joining codes, approval, authorization, RLS, Superadmin provisioning | Unauthorized users cannot reach team data; Admin approves a member safely; Superadmin bootstrap verified |
| 2 | Directory, operational roles, shifts, availability, Live Ops Board | Members see accurate shared status and coverage on mobile |
| 3 | Incidents, help requests, assignments, announcements, acknowledgements, in-app notifications | A simulated outage is coordinated from report to resolution |
| 4 | Handovers, unresolved items, knowledge notes, publishing, search | Incoming member continues unresolved work without private messages |
| 5 | PWA install, Web Push, E2E and security regression, deployment, recovery docs | All release-blocking checks pass; production configured |

No phase starts until the previous phase's exit gate is reviewed and approved by the owner.
