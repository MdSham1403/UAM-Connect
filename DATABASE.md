# DATABASE

**Status: PROPOSED. Nothing here is implemented.** No migrations exist. The schema must be reviewed, then implemented only through versioned SQL migrations in the phase that needs each table. Requirements: [PROJECT_SPEC](PROJECT_SPEC.md) · Controls: [SECURITY](SECURITY.md) · Design: [ARCHITECTURE](ARCHITECTURE.md).

## 1. Conventions

- PostgreSQL via Supabase. UUID primary keys (`gen_random_uuid()`), `timestamptz` in UTC, `created_at`/`updated_at` where relevant.
- `team_id` on every team-owned table (single team in v1; prevents future isolation problems). Every FK indexed.
- Reference roles and records by ID, never by name. Soft-deactivate (`is_active`, status, `archived_at`) where history must survive; no hard deletes of historical data in v1 (D-10).
- Enumerations as Postgres enums or `CHECK` constraints; text lengths bounded with `CHECK`.
- **RLS on every table.** "RLS expectation" below assumes helpers: `is_approved_member(team_id)`, `has_app_permission(team_id, key)`, `is_superadmin()`.
- Extensions: `pgcrypto` (hashing, UUID); `pg_trgm` optional for fuzzy search.
- Migration file naming: `YYYYMMDDHHMMSS_<description>.sql`, applied in order; each migration includes its RLS and policies.

## 2. Relationship overview

```
auth.users ─1:1─ profiles
auth.users ─1:N─ team_memberships ─N:1─ teams
team_memberships ─N:M─ app_roles            (member_app_roles)
team_memberships ─N:M─ operational_roles    (member_operational_roles)
auth.users ─0..1─ platform_owners           (Superadmin)
teams ─1:N─ join_codes ; join_requests ; shifts ; incidents ; help_requests ;
            announcements ; handovers ; knowledge_notes ; audit_logs
shifts ─1:N─ shift_assignments ─N:1─ team_memberships / operational_roles
incidents ─1:N─ incident_updates ; incident_participants
help_requests ─1:N─ help_request_volunteers
handovers ─1:N─ handover_items ─0..1→ incidents / help_requests
knowledge_notes ─1:N─ knowledge_revisions
team_memberships ─1:N─ notifications ; push_subscriptions ; availability(1:1)
```

## 3. Tables

### 3.1 Identity and authorization (Phase 1)

| Table | Key columns | Constraints / indexes | RLS expectation |
|---|---|---|---|
| `teams` | `id`, `name`, `timezone`, `incident_seq`, `created_at` | — | Approved members read own team; write Admin+ via function |
| `profiles` | `user_id` PK→`auth.users`, `display_name`, `organizational_title`, `avatar_path`, timestamps | length checks | Own row read/update (permitted columns); approved members read teammates; pending: own only |
| `team_memberships` | `id`, `team_id`, `user_id`, `membership_status` (`pending`/`approved`/`suspended`/`removed`), `approved_by`, `approved_at`, `suspended_at`, `reports_to_membership_id` (nullable, D-07) | `UNIQUE(team_id,user_id)`; index on `(team_id,membership_status)`; reports_to must be same team | Own row read; approved members read team rows; **no client writes**; changes via functions |
| `app_roles` | `id`, `team_id`, `key` (`member`/`team_lead`/`admin`), `name`, `permissions` (jsonb, allowlisted keys) | `UNIQUE(team_id,key)`; trigger validates permission keys | Read by approved members; write only by migration/Superadmin function |
| `member_app_roles` | `membership_id`, `app_role_id`, `granted_by`, `created_at` | PK `(membership_id,app_role_id)` | Own read; Admin+ read; **no client writes** |
| `platform_owners` | `user_id` PK→`auth.users`, `granted_at`, `granted_by` (null for bootstrap), `revoked_at`, `note` | Trigger blocks removing last active owner via app paths | Own row read only; **no client writes**; bootstrap by SQL in trusted environment |
| `operational_roles` | `id`, `team_id`, `name`, `description`, `color`, `icon`, `is_active`, `can_coordinate`, `created_by`, timestamps | `UNIQUE(team_id, lower(name))` among active; no delete (FK `RESTRICT`) | Approved read; Admin+ write via function |
| `member_operational_roles` | `membership_id`, `operational_role_id`, `is_primary`, `assigned_by`, `created_at` | PK `(membership_id,operational_role_id)`; partial unique: one primary per member (if single-primary chosen) | Approved read; Admin+ write |
| `join_codes` | `id`, `team_id`, `code_hash`, `label`, `expires_at`, `max_uses`, `use_count`, `created_by`, `revoked_at`, `revoked_by` | `UNIQUE(code_hash)`; `use_count <= max_uses` check | Admin+ read metadata; hash never exposed to clients; writes via functions |
| `join_requests` | `id`, `team_id`, `user_id`, `status` (`pending`/`approved`/`rejected`), `requested_at`, `reviewed_by`, `reviewed_at` | `UNIQUE(team_id,user_id)` while pending | Own read; Admin+ read/review via function |
| `rate_limit_events` | `id`, `user_id`, `action`, `created_at`, `meta` | Index `(user_id,action,created_at)` | **No client access**; written by functions only |
| `team_settings` | `team_id` PK, `settings` jsonb (allowlisted keys), `updated_by`, `updated_at` | Key allowlist trigger | Approved read (non-sensitive keys); Admin+ write via function |

### 3.2 Operations (Phase 2)

| Table | Key columns | Constraints / indexes | RLS expectation |
|---|---|---|---|
| `shifts` | `id`, `team_id`, `name`, `start_time`, `end_time`, `timezone`, `is_active` | Overnight allowed (D-12) | Approved read; Admin+ write |
| `shift_assignments` | `id`, `shift_id`, `membership_id`, `operational_role_id`, `work_date`, `coverage_status` (`expected`/`confirmed`/`absent`) | `UNIQUE(shift_id,membership_id,operational_role_id,work_date)`; index `(work_date)` | Approved read; Admin+ write; member confirms own |
| `availability` | `id`, `membership_id` UNIQUE, `status`, `note`, `expires_at`, `updated_at` | `status` in (`available`,`busy`,`on_break`,`off_shift`) | Approved read; **own row** write only |
| view `availability_effective` | `membership_id`, effective status (`unknown` if expired/stale) | Invoker security; stale threshold in settings | Inherits RLS |

### 3.3 Coordination (Phase 3)

| Table | Key columns | Constraints / indexes | RLS expectation |
|---|---|---|---|
| `incident_severities` | `id`, `team_id`, `name`, `rank`, `is_active` | `UNIQUE(team_id,name)` | Approved read; Admin+ write |
| `incidents` | `id`, `team_id`, `reference`, `title`, `description`, `affected_service`, `severity_id`, `status` (`open`/`investigating`/`monitoring`/`resolved`), `owner_membership_id`, `created_by`, `resolved_at`, `resolution_summary`, `reopen_reason` | `UNIQUE(team_id,reference)`; index `(team_id,status)`; resolved requires summary | Approved read/create; ownership/resolve only via functions per matrix |
| `incident_updates` | `id`, `incident_id`, `author_membership_id`, `update_type` (`note`/`status`/`assignment`/`system`), `message`, `created_at` | Immutable; index `(incident_id,created_at)` | Approved read/insert (own author); no update/delete |
| `incident_participants` | `incident_id`, `membership_id`, `participation_status` (`volunteered`/`active`/`left`), `joined_at` | PK `(incident_id,membership_id)` | Approved read; own insert/update |
| `help_requests` | `id`, `team_id`, `title`, `description`, `requested_role_id`, `requested_membership_id` (nullable), `priority`, `status` (`open`/`claimed`/`in_progress`/`completed`/`cancelled`), `requester_id`, `assignee_id`, `linked_incident_id`, `ticket_ref` | Index `(team_id,status)`; either role or person target | Approved read/create; assignment via function |
| `help_request_volunteers` | `help_request_id`, `membership_id`, `created_at` | PK pair | Approved read; own insert/delete |
| `announcements` | `id`, `team_id`, `title`, `body`, `category`, `author_id`, `is_pinned`, `expires_at`, `requires_acknowledgement`, `archived_at` | Index `(team_id,is_pinned,created_at)` | Approved read; Team Lead+ write via function |
| `announcement_acknowledgements` | `announcement_id`, `membership_id`, `acknowledged_at` | PK pair | Approved read counts per policy; own insert only |
| `notifications` | `id`, `membership_id`, `event_type`, `title`, `body`, `target_type`, `target_id`, `read_at`, `created_at` | Index `(membership_id, read_at, created_at)` | Own read; own `read_at` update only; inserts by functions |
| `notification_preferences` | `membership_id`, `event_type`, `in_app`, `push` | PK pair | Own read/write |

### 3.4 Continuity (Phase 4)

| Table | Key columns | Constraints / indexes | RLS expectation |
|---|---|---|---|
| `handovers` | `id`, `team_id`, `shift_id`, `outgoing_member_id`, `incoming_member_id`, `summary`, `status` (`draft`/`submitted`/`acknowledged`), `submitted_at`, `acknowledged_at` | Outgoing ≠ incoming | Approved read; author edits own draft; transitions via function |
| `handover_items` | `id`, `handover_id`, `item_type`, `title`, `description`, `owner_id`, `status` (`open`/`in_progress`/`resolved`/`reassigned`), `linked_incident_id`, `linked_help_request_id` | Index `(status, owner_id)`; submitting never changes `status` | Approved read; owner/coordinator update |
| `knowledge_notes` | `id`, `team_id`, `title`, `content`, `category`, `tags` text[], `status` (`draft`/`published`/`archived`), `author_id`, `published_at`, `search` tsvector (generated) | GIN index on `search` and `tags` | Published: approved read; drafts: author only; publish via function (Team Lead+) |
| `knowledge_revisions` | `id`, `note_id`, `revision_number`, `content_snapshot`, `edited_by`, `created_at` | `UNIQUE(note_id,revision_number)` | Read follows note visibility; insert via function |

### 3.5 Notifications delivery and audit (Phases 3–5)

| Table | Key columns | Constraints / indexes | RLS expectation |
|---|---|---|---|
| `push_subscriptions` | `id`, `membership_id`, `endpoint`, key material (storage approach R-07), `created_at`, `revoked_at` | `UNIQUE(endpoint)` | Own insert/revoke only; never returned by profile queries; sender reads via service role |
| `audit_logs` | `id`, `team_id`, `actor_user_id`, `action`, `entity_type`, `entity_id`, `metadata` jsonb, `created_at` | Index `(team_id,created_at)`; **append-only** (no update/delete grants) | Admin+ read; inserts only inside privileged functions |

## 4. Privileged functions (names proposed)

Defined in [ARCHITECTURE](ARCHITECTURE.md) §5. All are `SECURITY DEFINER`, fixed `search_path`, explicit caller check, `EXECUTE` limited to `authenticated`, and write `audit_logs` in the same transaction where listed in [SECURITY](SECURITY.md) §9.

## 5. Triggers and guards

- Prevent removal/revocation of the last active `platform_owners` row via application paths.
- Validate allowlisted keys on `app_roles.permissions` and `team_settings.settings`.
- Maintain `updated_at`; maintain `knowledge_notes.search`; create revisions on publish/edit.
- Reject FK targets belonging to a different `team_id`.
- Block deletes of `operational_roles` (and other referenced rows) with historical references.

## 6. Search

Generated `tsvector` over title (weight A), tags (B), content (C) with GIN index; query through a function returning only rows the caller may read.

## 7. Retention (D-10)

v1 keeps all data. Announcements expire/archive (hidden, not deleted); handovers remain; audit logs immutable. Revisit before production.

## 8. Migration order

1. Extensions, helper functions, `teams`, `profiles`, `team_memberships`, `app_roles` and seeds, `member_app_roles`, `platform_owners`, `audit_logs`.
2. `join_codes`, `join_requests`, `rate_limit_events`, membership functions.
3. `operational_roles` (+ assignments), `shifts`, `shift_assignments`, `availability`, view.
4. `incident_severities`, `incidents` (+ children), `help_requests` (+ volunteers), `announcements` (+ acknowledgements), `notifications`, `notification_preferences`, `team_settings`.
5. `handovers`, `handover_items`, `knowledge_notes`, `knowledge_revisions`.
6. `push_subscriptions` and sender wiring.

Each migration ships with policies and tests ([TEST_PLAN](TEST_PLAN.md)). A fresh environment must apply the full chain successfully (AC-S6).
