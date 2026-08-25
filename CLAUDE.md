# CLAUDE.md

Guidance for Claude Code working in this repo. Read this before every task.

## What we're building

A mobile app (Flutter) for organising events with friends — trips, dinners,
birthdays, meetups. Each event is a "ticket": title, description, status,
date, attachments, members, comments, and reactions. Think Jira stripped down
to the social essentials — **not** Jira's surface area. Backend is Supabase
(Postgres + Auth + Realtime + Storage).

## THE VISIBILITY RULE — read this twice

**Visibility equals membership, and it is enforced in the database, never in
the client.** A user can see an event (and its comments, reactions, polls,
expenses, attachments) if and only if a row links them to it in
`event_members`. Everything else in this file is detail; this is the part that
must not rot.

Therefore:

- **Never** filter events for visibility in Dart/Flutter. The client must
  assume the database already returned only what the user is allowed to see.
  Hiding something by not rendering it is a bug, not a feature — the data would
  still be on the device and fetchable.
- Every new table that hangs off an event carries `event_id` and gets an RLS
  policy `using (public.is_event_member(event_id))`. No exceptions.
- `is_event_member` / `is_event_organizer` are `SECURITY DEFINER` on purpose —
  that is what stops RLS recursion. Call them; never inline a membership
  subquery into a policy.

### Getting in: two doors, and only two

Membership is not something a client grants itself. It arrives either because

1. an **organizer adds you** (`event_members_insert_organizer`), or
2. you **open an invite link** and the join RPC adds you.

The join RPC is `SECURITY DEFINER` and therefore bypasses the insert policy —
possession of a valid, unexpired, unrevoked token *is* its authorization. The
same is true of `assign_group_to_event`. **So the
insert policy is not an exhaustive account of who can join.** Read those
functions too before reasoning about membership.

### Retired: the surprise mechanic (2026-08-21)

The app used to hide an event from one named person (`events.surprise_target`,
plus two guard triggers), and that was its original reason to exist. It was
**deliberately removed** — the column, the triggers, and the friend requirement
on adding members — because it is incompatible with join-by-link: a forwarded
link admits whoever holds it, and the guard matched on a `profiles.id` that a
new joiner does not have.

Do not reintroduce per-user content hiding, and do not treat its absence as an
oversight. If a feature seems to need it, that is a product conversation, not a
patch.

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
- `events` — the ticket. Visible to its members (see the visibility rule).
- `event_members` — membership == visibility. `role` (organizer/member), `rsvp`.
- `comments`, `reactions` (reactions carry `event_id` for RLS scoping).
- `attachments` — metadata; bytes in Storage bucket `event-attachments`,
  path `{event_id}/{filename}`.

Helper SQL functions `is_event_member(uuid)` and `is_event_organizer(uuid)` are
`SECURITY DEFINER` on purpose — that's what stops RLS recursion. Don't inline
membership subqueries into policies; call the functions.

## One branch

`master`, and only `master`. There is no chat or messaging in this app and no
branch exploring one — a `feature/chat` branch existed briefly on 2026-08-22 and
was deleted the same day, unused.

That is a decision, not a gap. Everyone using this app is already in a group
chat about the event — the invite link gets pasted into one. A second
conversation surface would compete with the one that has everyone's history,
and it would cost a permanent architectural tax: today visibility has exactly
one oracle, `is_event_member(event_id)`, and DMs plus group chat would add two
more axes to reason about forever. It also drags in push notifications and
user-to-user moderation, the latter being a Play Store review blocker.

Comments on an event are NOT chat. They exist, they stay, and they already
carry threads, reactions and @mentions.

If chat comes back it is a product conversation with a real trigger behind it
(people repeatedly wanting to say something and having nowhere to put it,
most likely in friend groups) — not a patch.

## Retired: crews (2026-08-23)

There used to be TWO group concepts. `friend_groups` (owner-private selection
shortcut) survives. `crews` (shared, visible circles where every member saw the
roster) were removed — two tables, two RLS models, two screens and two
notification paths for one user-facing idea.

`friend_groups` keeps the part that mattered: `assign_group_to_event` still
expands a group into individual `event_members` rows in one tap. What was lost
is only the shared roster. Do not reintroduce a second group type; if a group
needs to be visible to its members, that is a change to `friend_groups`, not a
new table beside it.

`crews.sql` became `notifications.sql` — the notification system lived in the
same file and was never crew-specific.

## Scope discipline

This is "Jira without the unnecessary parts." Resist rebuilding Jira.

In scope (v1): events with a small fixed status set
(idea → planning → confirmed → done/cancelled), members,
comments, reactions, attachments, simple RSVP, join-by-link, expenses
with equal-split settle-up (Tricount-style: log who paid and who it's split
between; the app computes a minimum-transaction settle-up — read-only, no
"mark as paid").

Out of scope (do not add without an explicit request): custom workflow engines,
custom fields, dashboards/reporting, labels, saved filters, a web app.
Date-polling is explicitly **v2** — don't pull it forward. Expense-splitting
extensions (unequal/custom splits, multi-currency, marking transfers as
settled) are also v2 — the v1 expenses feature is equal-split-only, read-only
settle-up.

Assignable sub-items ("who brings dessert" — the old Items tab) were
**deliberately removed** to cut UI clutter. Do not reintroduce them.

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

Backend: apply these in the Supabase SQL editor **in order** — later files
depend on tables the earlier ones create:

1. `schema.sql` — events, members, comments, reactions, attachments.
2. `social_layer.sql` — friends, groups, notifications.
3. `event_types.sql` — the creation templates.
4. `notifications.sql` — the per-recipient notification table and triggers.
5. `polls.sql` — per-event polls, majority / weighted-random resolution.
6. `polls_multivote.sql` — widens the vote key so a member can back several
   options in one poll, and adds the distinct-voter count RPC.
7. `activity_feed.sql` — `event_members.rsvp_at` (stamped only when an answer
   changes) plus the expense notification, both of which the Home feed reads.
8. `avatars.sql` — the public `avatars` Storage bucket and its owner-scoped
   write policies.

Then run `rls_tests.sql` to confirm the visibility model holds.

Files 6–8 are migrations against an already-applied `schema.sql`/`polls.sql`,
not standalone schemas. Skipping one does not fail loudly: the app compiles and
most of it works, but the Home feed 42703s on the missing `rsvp_at` column and
takes the whole feed down with it. If a feature is inexplicably broken on a
fresh database, check this list first.
