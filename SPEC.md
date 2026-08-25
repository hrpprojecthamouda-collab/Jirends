# Jirends — Frozen Specification (v1)

This document freezes the v1 feature set as user stories, so it can serve as
the baseline for `TEST_PLAN.md`. It describes **what the app currently does**,
verified against the actual code and schema — not aspirational features.
Anything not listed here is out of scope for this freeze (see CLAUDE.md's
scope section for what's explicitly deferred to v2).

Conventions used below:
- **As a / I want / So that** — standard user story shape.
- **US-<area>-<n>** — story id, referenced by test cases in TEST_PLAN.md.
- Each story includes its **actors** (which role/relationship is required).

---

## 0. Visibility & Permissions (cross-cutting)

The app's defining property: **every user has a visibility scope specific to
them**, enforced in the database (RLS), never in the client. No screen ever
decides what to hide — it only ever renders what the backend returned. The
boundaries below are the complete catalog; every feature section after this
one operates inside one or more of them.

| # | Boundary | Rule |
|---|----------|------|
| VIS-1 | **Event membership** | A user sees an event (and everything hanging off it — items, comments, reactions, attachments, polls, history, expenses) **iff** a row links them to it in `event_members`. No exceptions, no client-side filtering. |
| VIS-2 | ~~**Surprise target**~~ **RETIRED 2026-08-21** | Was: an event could name one person as `surprise_target` and hide itself from them. Removed along with its two guard triggers and the friend requirement on adding members, because it is incompatible with join-by-link — a forwarded link admits whoever holds it, and the guard matched on a profile id a new joiner does not have. |
| VIS-3 | **Organizer vs member** | Within an event, only organizers may: add/remove members, edit the event, advance/cancel its status, delete it, create date/time/place polls, delete others' items/comments/expenses. Plain members may RSVP, add items/comments/expenses, vote, and act on their own content. An event must always keep ≥1 organizer (last-organizer guard). |
| VIS-4 | **Friends are mutual, scoped to the owner** | Friend lists are private to the owner; adding is mutual (no accept step) but **removal is one-sided** — removing someone doesn't remove you from their list. |
| VIS-5 | **Selection groups are private** | A "group" (Type 1) is a private shortcut owned by one user to batch-add friends to an event. Members are never notified and never see each other or the group itself. |
| VIS-6 | ~~**Crews are shared/visible**~~ **RETIRED 2026-08-23** | Crews (Type 2, shared visible circles) were removed. `friend_groups` keeps the part that mattered — adding several people to an event in one tap — and two group concepts with divergent visibility rules were not worth two tables, two RLS models and two screens. |
| VIS-7 | ~~**Poll vote privacy**~~ **RETIRED** | Was: while a poll is open, each voter sees only their own vote. Retired by product decision — members press-and-hold a poll option to see who backed it, so votes are readable by any event member at any time. Membership still gates them (`poll_votes_select`). |
| VIS-8 | **Conflict checks are boolean-only for third parties** | Checking whether *someone else* has a scheduling conflict returns a yes/no flag and never names the conflicting event. Checking your **own** conflicts returns full event titles (you're already a member of both). |
| VIS-9 | **Notifications are per-recipient** | A user only ever reads their own notification rows, and no notification is ever generated for a non-member about an event they cannot see. |
| VIS-10 | **History is member-scoped, tamper-proof** | The audit log inherits event membership visibility and is written only by server-side triggers — no client insert path. |

---

## 1. Authentication & Onboarding

**US-AUTH-1**: As a new user, I want to create an account with email/password,
so that I can start using the app. *(Actors: anonymous)*

**US-AUTH-2**: As a returning user, I want to sign in with email/password, so
that I can access my events and friends.

**US-AUTH-3**: As a signed-in user, I want to sign out, so that I can switch
accounts or stop a session on a shared device.

**US-AUTH-4**: As a newly-confirmed user, I want to choose a unique handle
(`nickname#tagline`), so that friends can find and add me. The handle must be
globally unique and is required before I can use the rest of the app.

---

## 2. Events — Core

**US-EVT-1**: As an organizer, I want to create an event with a type (trip,
dinner, birthday, meetup), title, optional description, date(s)/time,
location, so that I can start planning.

**US-EVT-2**: As an organizer, I want to edit an event's title, description,
times, and location after creating it, so that I can correct or refine plans.

**US-EVT-3**: As an organizer, I want to advance an event through its type's
phases (e.g. idea → planning → confirmed → done, or → cancelled), so that
everyone can see how settled the plan is. Only valid phases for that event's
type are selectable.

**US-EVT-4**: As an organizer, I want to delete an event, so that I can
remove one that's no longer happening. Deleting cascades all its data
(members, items, comments, polls, attachments, expenses, history).

**US-EVT-5**: As a member, I want to share an event via a copyable link, so
that I can reference it outside the app (the link only opens for people who
are already members — it's a convenience, not a public share).

**US-EVT-6**: As any user, I want to browse my events in a list or an agenda
(calendar) view, so that I can see what's coming up.

---

## 3. Members & RSVP

**US-MEM-1**: As an organizer, I want to add one of my friends as a member,
so that they can see and participate in the event. (Requires: the person is
already my friend.)

**US-MEM-2**: As an organizer, I want to add a whole selection group
at once, so that I don't have to add people one by one. This is a one-time
snapshot at add-time — adding someone to the group later does not
retroactively add them to past events.

**US-MEM-3**: As an organizer, I want to remove a member, so that I can
correct a mistaken add or reflect someone dropping out.

**US-MEM-4**: As a member, I want to leave an event myself, so that I'm no
longer associated with it. (Blocked if I'm the last organizer — see VIS-3.)

**US-MEM-5**: As a member, I want to set my own RSVP (going / maybe /
declined), so that the organizer knows my plans.

**US-MEM-6**: As an organizer adding someone, I want to be warned if the
person I just added has a scheduling conflict, so that I can flag it without
the warning ever naming the other event (see VIS-8).

---

## 4. Items (Checklist)

**US-ITEM-1**: As a member, I want to add an item to the event's checklist
("who brings dessert"), so that tasks are tracked.

**US-ITEM-2**: As a member, I want to tick/untick an item as done, so that
progress is visible to everyone.

**US-ITEM-3**: As a member, I want to claim an item for myself or assign it
to another member, so that responsibility is clear.

**US-ITEM-4**: As the item's creator or an organizer, I want to delete an
item, so that obsolete tasks don't clutter the list.

---

## 5. Comments, Discussions & Reactions

**US-COM-1**: As a member, I want to post a comment on an event, so that I
can discuss it with the other members.

**US-COM-2**: As a member, I want to reply to a comment, forming a named
discussion thread, so that side-conversations stay organized. Threads are
two levels deep only (no replies-to-replies).

**US-COM-3**: As any member, I want to name a discussion thread, so that its
topic is clear at a glance.

**US-COM-4**: As the comment's author, I want to edit my own comment, so
that I can fix mistakes. (No one else may edit my comment, including
organizers.)

**US-COM-5**: As the comment's author or an organizer, I want to delete a
comment, so that I can remove something posted in error.

**US-COM-6**: As a member, I want to react to an event or a comment with an
emoji, so that I can give lightweight feedback. Reacting again with the same
emoji removes it (toggle).

---

## 6. Attachments

**US-FILE-1**: As a member, I want to upload a file (itinerary, ticket,
photo) to the event, so that it's available to everyone.

**US-FILE-2**: As a member, I want to open an attachment, so that I can view
its contents (via a time-limited signed link).

**US-FILE-3**: As the uploader or an organizer, I want to delete an
attachment, so that outdated or wrong files don't linger.

---

## 7. Polls

**US-POLL-1**: As a member, I want to create a general poll (free question,
text options), so that the group can decide something together.

**US-POLL-2**: As an organizer, I want to create a date, time, or place poll,
so that closing it automatically applies the winning choice to the event.
(Only organizers may create these three kinds — they directly affect the
event's recorded date/time/location.)

**US-POLL-3**: As a member, I want to cast one vote per poll, and to change
my vote while it's open, so that I can participate in the decision.

**US-POLL-4**: As the poll's creator, I want to close the poll, so that the
result (majority, or a one-time weighted-random draw) is finalized. A tie
under majority mode produces no winner.

**US-POLL-5**: As the poll's creator, I want to reopen a closed poll, so
that I can correct a premature close.

**US-POLL-6**: As the poll's creator or an organizer, I want to delete a
poll, so that an irrelevant or duplicate poll can be removed.

---

## 8. History

**US-HIST-1**: As a member, I want to see a read-only audit log of what
changed on the event (field edits, status changes, poll lifecycle events,
and who did them), so that I can catch up on what happened.

---

## 9. Expenses (Tricount-style settle-up)

**US-EXP-1**: As a member, I want to log an expense — what I paid, a
description, and who it's split between (defaulting to everyone) — so that
shared costs are tracked. The split is always equal among the chosen
participants; an uneven division's leftover cent(s) land on the last
participant so the shares always sum exactly to the total.

**US-EXP-2**: As any member, I want to see a live "settle up" summary
showing the minimum number of payments needed to balance everyone's
expenses, so that the group doesn't have to do the math. This is always
computed fresh from the expense ledger — there is no "mark as paid" action.

**US-EXP-3**: As the expense's creator or an organizer, I want to delete an
expense, so that mistakes can be corrected (there is no edit — delete and
re-add is the v1 correction path).

*Out of scope for v1 (explicitly deferred): unequal/custom splits, a
currency field, marking a suggested transfer as settled.*

---

## 10. Friends

**US-FRD-1**: As a user, I want to add another user as a friend by their
handle, so that I can add them to events. Adding is mutual — no accept step
is needed, and the other person sees me as a friend immediately too.

**US-FRD-2**: As a user, I want to remove a friend, so that I no longer see
them as a candidate for events. This only affects my own list (VIS-4).

---

## 11. Groups (private)

**US-GRP-1**: As a user, I want to create a private selection group of my
friends, so that I can quickly add the same set of people to multiple
events. (Group members are never notified and never see each other.)

**US-GRP-2**: As a group's owner, I want to add/remove friends from it and
rename or delete it, so that I can keep it current.



## 12. Notifications

**US-NOTIF-1**: As a user, I want to be notified when someone adds me as a
friend or adds me to an event, so that I know what
changed without checking manually.

**US-NOTIF-2**: As a user, I want to be notified when an event I'm in is
confirmed or cancelled, so that I'm kept in the loop on its status. I am not
notified about my own actions (no self-notification).

**US-NOTIF-3**: As a user, I want to mark my notifications as read, so that
my unread count reflects what I've actually seen.

*(VIS-9 governs: a non-member never receives any notification tied to
the event they're hidden from.)*

---

## 13. Home Activity Feed

**US-HOME-1**: As a user, I want to see a feed of recent activity (comments,
new items) across the events I'm a member of, so that I have a quick
overview without opening each event.

---

## 14. Profile & Settings

**US-PROF-1**: As a user, I want to view my own profile (handle, avatar), so
that I can confirm how others see me.

**US-SET-1**: As a user, I want to switch the app's language between
English, French, and Tunisian (Derja), so that I can use the app in my
preferred language.

**US-SET-2**: As a user, I want to sign out from Settings, so that I can end
my session.

---

## Out of scope for this freeze

Per CLAUDE.md, explicitly deferred to v2 and not covered by this spec or its
test plan: date-polling pulled forward beyond what's listed above, custom
workflow engines, custom fields, dashboards/reporting, labels, saved
filters, a web app, unequal/custom expense splits, multi-currency, and
marking expense transfers as settled.
