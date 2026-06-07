# CLAUDE.md

Guidance for Claude Code working in this repo. Read this before every task.

## What we're building

A mobile app (Flutter) for organising events with friends — trips, dinners,
birthdays, meetups. Each event is a "ticket": title, description, a per-type
workflow, type-specific properties, attachments, members, comments, reactions,
and assignable sub-items ("who brings dessert"). It has a light social graph
(friends + friend groups) for choosing who to invite. Think Jira stripped to
the social essentials — **not** Jira's surface area, and **not** a
user-configurable workflow builder. Backend is Supabase (Postgres + Auth +
Realtime + Storage). The schema is the source of truth: `schema.sql`,
`social_layer.sql`, `event_types.sql` (applied in that order).

## THE CARDINAL RULE — read this twice

**Visibility equals membership, and it is enforced in the database, never in
the client.** A user can see an event (and its comments, items, reactions,
attachments) if and only if a row links them to it in `event_members`. A
"surprise birthday party" must be physically unreadable to its target.

Therefore:

- **Never** filter events for visibility in Dart. The client assumes the
  database already returned only what the user may see. Hiding a surprise by
  not rendering it is a bug — the data would still be on the device.
- Every table hanging off an event carries `event_id` and an RLS policy
  `using (public.is_event_member(event_id))`. No exceptions.
- The surprise target is enforced twice: not added as a member, **and** a
  trigger refuses to add them. Don't weaken either.
- Watch side channels: no push notification to a surprise target, no
  "added to X" naming the event, no free-busy view leaking a hidden event.
- If a task seems to need client-side visibility enforcement, stop and flag
  it — the design is wrong, not the rule.

## Social graph (friends & groups) — two more invariants

- **Friends are directional, no request/accept.** You add someone by handle
  (`nickname#tagline`, e.g. `Sparrow#TheCrew`) via `add_friend_by_handle(...)`.
  That puts them in *your* address book only; it does not add you to theirs.
  `is_friend(uid)` means "in MY address book".
- **Friend groups are a selection shortcut, never a permission.** A group is
  NEVER linked to an event. To invite a group, expand it into individual
  `event_members` rows at add-time via `assign_group_to_event(group, event)`.
  Do **not** tie event visibility to live group membership — adding someone to
  a group later must never retroactively expose past events. `event_members`
  stays the single source of truth for visibility.
- Adding an individual to an event requires them to be your friend
  (`is_event_organizer AND is_friend` on the insert). The batch group function
  validates ownership/organizer itself.

## Event types: phases & properties are DATA, not code

- Event types are developer-defined (the `event_type` enum). Their workflows
  and fields live in seeded definition tables, not in Dart and not in a runtime
  builder.
- **Status is a phase key**, validated by a composite FK
  `(event_type, status) -> event_type_phases(event_type, key)`. The DB refuses
  to put an event into a phase its type doesn't have. New events auto-start at
  their type's first phase (lowest `position`).
  - **Never hardcode the status list in Dart.** Load phases for the type from
    `event_type_phases` and render the workflow from that. Phases are a linear
    ordered sequence (advance by `position`); there is no transition-graph rule
    yet — the FK only validates that a phase belongs to the type.
- **Type-specific properties**: definitions live in `event_type_fields`
  (key, label, datatype, is_required, position). Values live in
  `events.properties` (JSONB). Render forms from the field defs; the app
  validates required/types. The DB stores JSON permissively.
- `event_type_phases` and `event_type_fields` are app config: read-only to
  users (RLS allows select only). Fetch once and cache.

## Use the SQL primitives — don't reimplement logic in Dart

`is_event_member`, `is_event_organizer`, `is_friend`, `add_friend_by_handle`,
`assign_group_to_event`. Membership, friendship, and group expansion are
decided in Postgres. The repositories call these; they don't re-derive the
rules client-side.

## Stack

- **Flutter** (Dart) — single codebase, iOS + Android.
- **Riverpod** — state; pairs with Supabase realtime streams.
- **Supabase** — Postgres, Auth, Realtime, Storage (`supabase_flutter`).
- **freezed** + **json_serializable** — models & (de)serialization.
- **go_router** — navigation.
- Repository pattern between UI and Supabase.

## Architecture

Layers: UI (dumb widgets) → Controllers/Notifiers (Riverpod) → Repositories
(the only layer that touches Supabase; returns domain models) → Models
(freezed). No Supabase calls or business/visibility logic in widgets.

Build in **vertical slices**: one feature end-to-end (model → repository →
controller → screen) before the next. Keep the app runnable at every commit.

## Data model (see the SQL files for source of truth)

- `profiles` — mirror of `auth.users`; `nickname` + `tagline` form the unique,
  case-insensitive handle (set during onboarding).
- `events` — the ticket. `event_type` (enum), `status` (phase key, FK-validated),
  `properties` (JSONB), `surprise_target` (the user it's hidden from).
- `event_members` — membership == visibility. `role`, `rsvp`.
- `event_items`, `comments`, `reactions`, `attachments`.
- `friends` — directional address book.
- `friend_groups`, `friend_group_members` — owner-private; selection only.
- `event_type_phases`, `event_type_fields` — per-type config, read-only.

Membership/friend helper functions are `SECURITY DEFINER` to avoid RLS
recursion; call them rather than inlining subqueries into policies.

## Scope discipline

In scope (v1): events with per-type phases & fields (defined as seed data),
members, assignable items, comments, reactions, attachments, RSVP, the surprise
mechanic, friends-by-handle, friend groups.

Out of scope (don't build without an explicit request): a user-facing workflow
/ type / field **builder**, transition-graph rules between phases, custom roles,
dashboards/reporting, a web app. Date-polling and expense-splitting are **v2**.

## Conventions

- Immutable freezed models; async via `AsyncValue` / `AsyncNotifier`; never
  swallow errors. Repositories throw typed failures; controllers map them to
  user-facing messages — no raw `PostgrestException` in the UI.
- Catch the unique-violation on handle/profile updates and surface "handle
  taken".
- Names: `EventRepository`, `eventListProvider`, `EventDetailController`, etc.
- Keep widgets small (extract over ~150 lines). No new top-level deps without a
  note on why.

## Working agreement

- **RLS tests are the spec.** `rls_tests.sql` must pass before any change that
  touches visibility, friends, membership, or status validity.
- Small, bounded commits — one slice or fix each.
- When a task is ambiguous about visibility/permissions, ask, don't guess.
- Reuse from the sibling TIDY project where it helps (design tokens, audio/UI
  patterns, auth scaffolding).

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

Backend: apply `schema.sql`, then `social_layer.sql`, `event_types.sql`, then
`crews.sql` (shared/visible "crew" groups — Type 2) in the Supabase SQL editor,
then run `rls_tests.sql` to confirm the model holds.
