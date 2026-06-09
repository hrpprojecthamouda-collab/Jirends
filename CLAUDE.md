# CLAUDE.md

Guidance for Claude Code working in this repo. Read this before every task.

## What we're building

A mobile app (Flutter) for organising events with friends — trips, dinners,
birthdays, meetups. Each event is a "ticket": title, description, status,
date, attachments, members, comments, reactions, and assignable sub-items
("who brings dessert"). Think Jira stripped down to the social essentials —
**not** Jira's surface area. Backend is Supabase (Postgres + Auth + Realtime +
Storage).

## THE CARDINAL RULE — read this twice

**Visibility equals membership, and it is enforced in the database, never in
the client.** A user can see an event (and its comments, items, reactions,
attachments) if and only if a row links them to it in `event_members`. This is
the entire reason the app exists: a "surprise birthday party" must be
physically unreadable to its target.

Therefore:

- **Never** filter events for visibility in Dart/Flutter. The client must
  assume the database already returned only what the user is allowed to see.
  Hiding a surprise by not rendering it is a bug, not a feature — the data
  would still be on the device and fetchable.
- Every new table that hangs off an event carries `event_id` and gets an RLS
  policy `using (public.is_event_member(event_id))`. No exceptions.
- The surprise target is enforced two ways: they're simply not added as a
  member, **and** a `BEFORE INSERT` trigger refuses to add them. Don't weaken
  either.
- Watch the side channels, not just the main screen. No push notification to a
  surprise target, no "you were added to X" that names the event, no
  calendar/free-busy view that leaks "you're booked 8–10pm" pointing at a
  hidden event. When adding any feature, ask: "can the target infer the
  surprise from this?"

If a task seems to require enforcing visibility in the client, stop and flag
it — the design is wrong, not the rule.

## Stack

- **Flutter** (Dart) — single codebase, iOS + Android.
- **Riverpod** — state management; pairs with Supabase realtime streams.
- **Supabase** — Postgres, Auth, Realtime, Storage. SDK: `supabase_flutter`.
- **freezed** + **json_serializable** — immutable models & (de)serialization.
- **go_router** — navigation.
- Repository pattern between UI and Supabase (see Architecture).

## Architecture

Layers, top to bottom:

1. **UI (widgets/screens)** — dumb. Reads state from Riverpod providers, calls
   methods on controllers/notifiers. No Supabase calls, no business logic, no
   visibility logic.
2. **Controllers / Notifiers (Riverpod)** — orchestrate use-cases, expose state.
3. **Repositories** — the only layer that talks to Supabase. One repository per
   aggregate (`EventRepository`, `CommentRepository`, ...). Returns domain
   models, never raw maps. This seam is mandatory: it's where realtime streams,
   error mapping, and any future caching live, and it keeps tasks bounded.
4. **Models** — freezed classes mirroring the DB tables.

Build in **vertical slices**: one feature working end-to-end (model → repository
→ controller → screen) before starting the next. Do not build all the models,
then all the repositories. Keep the app runnable at every commit.

## Data model (see `schema.sql` for the source of truth)

- `profiles` — mirror of `auth.users`, auto-created on signup.
- `events` — the ticket. `surprise_target` (nullable) = the user it's hidden from.
- `event_members` — membership == visibility. `role` (organizer/member), `rsvp`.
- `event_items` — assignable sub-tasks.
- `comments`, `reactions` (reactions carry `event_id` for RLS scoping).
- `attachments` — metadata; bytes in Storage bucket `event-attachments`,
  path `{event_id}/{filename}`.

Helper SQL functions `is_event_member(uuid)` and `is_event_organizer(uuid)` are
`SECURITY DEFINER` on purpose — that's what stops RLS recursion. Don't inline
membership subqueries into policies; call the functions.

## Scope discipline

This is "Jira without the unnecessary parts." Resist rebuilding Jira.

In scope (v1): events with a small fixed status set
(idea → planning → confirmed → done/cancelled), members, assignable items,
comments, reactions, attachments, simple RSVP, the surprise mechanic.

Out of scope (do not add without an explicit request): custom workflow engines,
custom fields, dashboards/reporting, labels, saved filters, a web app.
Date-polling and expense-splitting are explicitly **v2** — don't pull them
forward.

## Conventions

- Immutable models (freezed). No mutable public fields.
- Async data via `AsyncValue` / `AsyncNotifier`; handle loading & error states
  in the UI, never swallow errors.
- Repository methods throw typed failures; controllers map them to user-facing
  messages. No raw `PostgrestException` reaching the UI.
- Names: `EventRepository`, `eventListProvider`, `EventDetailController`, etc.
- Keep widgets small; extract anything over ~150 lines.
- Don't introduce new top-level dependencies without noting why in the PR.

## Working agreement

- **RLS tests are the spec.** `rls_tests.sql` must pass before any
  visibility-touching change is considered done. If you change policies, run it.
- Small, bounded commits. One slice or one fix per commit.
- When a task is ambiguous about visibility/permissions, ask rather than guess.
- Reuse from the sibling TIDY project where it helps (design tokens, audio/UI
  patterns, auth scaffolding) rather than reinventing.

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # freezed/json
flutter analyze
flutter test
flutter run                                                  # device/emulator
```

Backend: apply `schema.sql`, then `social_layer.sql`, `event_types.sql`,
`crews.sql` (shared/visible "crew" groups — Type 2), and `polls.sql` (per-event
polls with majority / weighted-random resolution) in the Supabase SQL editor,
then run `rls_tests.sql` to confirm the visibility model holds.
