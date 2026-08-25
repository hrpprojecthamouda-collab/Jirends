# Jirends — Manual Test Plan (v1)

Traces to `SPEC.md`. Run by hand on a device/emulator (or via the debug
account switcher to move between test users quickly — see Setup). Each case
has Steps + Expected; check it off when it matches. File a note against the
case id when it doesn't, rather than editing the expected result, so drift
between spec and app is visible.

Test cases are numbered `TC-<area>-<n>` and link back to one or more
`US-...` / `VIS-...` ids from SPEC.md.

## Setup

- At least **5 test accounts**: Alice, Bob, Carol, Dave, Eve. Suggested roles
  used throughout this plan:
  - **Alice** — primary organizer for most scenarios.
  - **Bob, Carol** — ordinary members / friends of Alice.
  - **Dave** — used as a **non-member** in the visibility track; also a
  - **Eve** — a **stranger**: not friended by anyone, used for negative
    cases (handle lookup, non-member access attempts).
- The debug account switcher (Settings, dev builds only) is the fast path to
  swap between these without re-entering credentials each time.
- Two physical/emulated devices (or two app instances) makes the realtime
  and cross-user cases (notifications, conflicts, vote privacy) much faster
  to observe than swapping accounts on one device.
- Run this plan **after** `rls_tests.sql` passes — this plan checks the UI
  surfaces the DB-enforced behavior correctly, it does not re-derive backend
  correctness from scratch.

---

## 0. Visibility & Permissions

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-VIS-1 | Non-member can't open an event by guessing its id | As Eve, navigate directly to another user's event URL/route (e.g. via deep link) | "This event isn't available" — indistinguishable from a non-existent event | VIS-1 |
| TC-VIS-2 | Member sees all event children | As Bob (a member), open Overview/Members/Items/Polls/Comments/Files/History/Expenses tabs | All tabs load data normally | VIS-1 |
| TC-VIS-3 | Non-member sees nothing | Alice creates an event without Dave. As Dave, check: events list, agenda, direct link to the event | Event never appears anywhere for Dave; direct link shows "unavailable" | VIS-1, US-EVT-1 |
| TC-VIS-4 | ~~Surprise target can't be force-added~~ **RETIRED with VIS-2** | — | — | — |
| TC-VIS-5 | ~~Surprise badge~~ **RETIRED with VIS-2** | — | — | — |
| TC-VIS-6 | Only organizers can add/remove members | As Bob (plain member), confirm no add-member control is visible; attempting the underlying action fails | UI hides the control; any forced attempt is rejected | VIS-3 |
| TC-VIS-7 | Last-organizer guard | As Alice, sole organizer, try to leave the event or demote yourself | Action blocked with an explanit message | VIS-3, US-MEM-4 |
| TC-VIS-8 | Second organizer enables the first to leave | Promote Bob to organizer, then have Alice leave | Alice leaves successfully; Bob remains organizer | VIS-3 |
| TC-VIS-9 | Friend removal is one-sided | Alice removes Bob as a friend | Alice no longer sees Bob as a friend; Bob still sees Alice as his friend | VIS-4, US-FRD-2 |
| TC-VIS-10 | Selection group members don't see each other | Alice creates a group with Bob and Carol in it | Neither Bob nor Carol can see the group or know they're in it together | VIS-5, US-GRP-1 |
| TC-VIS-11 | ~~Crew roster visible to all members~~ **RETIRED with VIS-6** | — | — | — |
| TC-VIS-12 | ~~Crew co-membership is not event visibility~~ **RETIRED with VIS-6** | — | — | — |
| TC-VIS-13 | ~~Open poll hides others' votes~~ **RETIRED with VIS-7** | Bob and Carol vote in an open poll. As Carol, press-and-hold the option Bob backed | Bob is listed among the voters. Ballot secrecy is no longer a requirement | US-POLL-3 |
| TC-VIS-14 | Votes stay member-only | As a non-member of the event, attempt to read `poll_votes` for it | No rows. Retiring VIS-7 widened visibility to every MEMBER, not to everyone | VIS-1, US-POLL-4 |
| TC-VIS-15 | Third-party conflict check is boolean-only | As Alice, view Bob's conflict badge on a member tile where Bob's conflicting event is one Alice can't see | Badge shows a generic warning, never the other event's name | VIS-8, US-MEM-6 |
| TC-VIS-16 | Own conflict check shows full titles | As Bob, view your own conflicting-events list/banner | Full titles of your other overlapping events are shown | VIS-8 |
| TC-VIS-17 | Non-member gets no event notifications | Have an event Dave is NOT in go through member-add / confirm / cancel | Dave receives zero notifications tied to that event | VIS-9, US-NOTIF-1/2 |
| TC-VIS-18 | History is member-scoped | As Dave (non-member), confirm the event's History tab is unreachable; as Bob (member), confirm it shows entries | Dave: no access. Bob: sees the log | VIS-10, US-HIST-1 |

---

## 1. Authentication & Onboarding

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-AUTH-1 | Sign up | New email/password → submit | Account created; confirmation flow as configured | US-AUTH-1 |
| TC-AUTH-2 | Sign in | Existing credentials → submit | Lands on Home | US-AUTH-2 |
| TC-AUTH-3 | Sign in with wrong password | Wrong password → submit | Clear error, no crash | US-AUTH-2 |
| TC-AUTH-4 | Sign out | Settings → Sign out | Returns to sign-in screen; session cleared | US-AUTH-3 |
| TC-AUTH-5 | Onboarding handle required | First sign-in after confirmation, before setting a handle | Forced to Onboarding; can't reach the rest of the app | US-AUTH-4 |
| TC-AUTH-6 | Handle uniqueness | Try to claim a handle (nickname#tagline) already taken (any case) | Rejected with a clear message | US-AUTH-4 |
| TC-AUTH-7 | Handle persists | Set handle, sign out, sign back in | Handle still set; not asked to onboard again | US-AUTH-4 |

---

## 2. Events — Core

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-EVT-1 | Create each event type | Create one event of each type: trip, dinner, birthday, meetup | All four create successfully with type-appropriate fields (trip = date range, others = single date+time) | US-EVT-1 |
| TC-EVT-2 | ~~Create with surprise target~~ **RETIRED with VIS-2** | — | — | — |
| TC-EVT-3 | Create without required fields | Submit with no title | Blocked with a validation message | US-EVT-1 |
| TC-EVT-4 | Edit event fields | As organizer, change title/description/times/location | Changes saved and reflected immediately; logged in History | US-EVT-2, US-HIST-1 |
| TC-EVT-5 | Non-organizer can't edit | As Bob (member), confirm no edit control on event fields | UI doesn't expose editing | VIS-3, US-EVT-2 |
| TC-EVT-6 | Advance status through valid phases | As organizer, advance idea → planning → confirmed → done for a dinner | Each transition succeeds; only that type's phases are offered | US-EVT-3 |
| TC-EVT-7 | Cancel an event | As organizer, set status to cancelled | Status reflects cancelled; members notified (US-NOTIF-2) | US-EVT-3 |
| TC-EVT-8 | Delete event cascades | Delete an event with members/items/comments/polls/attachments/expenses | Event and all child rows disappear; no orphaned data visible anywhere | US-EVT-4 |
| TC-EVT-9 | Non-organizer can't delete | As Bob, confirm no delete control | UI doesn't expose it | VIS-3, US-EVT-4 |
| TC-EVT-10 | Share link | Copy event link, open it as a member on another device | Opens directly to the event | US-EVT-5 |
| TC-EVT-11 | Share link as non-member | Open the same link as Eve (stranger) | "Unavailable", not an error/crash | US-EVT-5, VIS-1 |
| TC-EVT-12 | List vs agenda view | Toggle between list and agenda/calendar view on Events | Both show the same set of visible events; agenda groups by day correctly | US-EVT-6 |

---

## 3. Members & RSVP

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-MEM-1 | Add a friend as member | As organizer, add Bob (already a friend) | Bob appears in the member list; Bob gets a notification (US-NOTIF-1) | US-MEM-1 |
| TC-MEM-2 | Can't add a non-friend | Try to add Eve (not a friend) | Not offered as a candidate, or rejected if attempted | US-MEM-1, VIS-4 |
| TC-MEM-3 | Add a selection group | Add a group containing Bob and Carol | Both added in one action; notified individually | US-MEM-2 |
| TC-MEM-4 | ~~Add a crew~~ **RETIRED with VIS-6** | — | — | — |
| TC-MEM-5 | Late group addition doesn't retro-expose | Add Carol to a group after that group was already used to populate an event | Carol is not retroactively added to the earlier event | US-MEM-2, VIS-5 |
| TC-MEM-6 | Remove a member | As organizer, remove Bob | Bob loses access to the event immediately | US-MEM-3 |
| TC-MEM-7 | Leave as a non-last organizer / as a member | As Bob (plain member), leave the event | Bob's own membership removed; event continues | US-MEM-4 |
| TC-MEM-8 | Set own RSVP | As Bob, set RSVP to going, then maybe, then declined | Each change is saved and visible to other members immediately | US-MEM-5 |
| TC-MEM-9 | Conflict warning on add | Add a member who has another event at the same time as this one | Warning shown naming the person, not the other event | US-MEM-6, VIS-8 |

---

## 4. Items

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-ITEM-1 | Add item | As any member, add "Bring dessert" | Appears in the checklist for all members | US-ITEM-1 |
| TC-ITEM-2 | Tick/untick | Mark it done, then undo | State toggles and is visible to all members | US-ITEM-2 |
| TC-ITEM-3 | Claim | As Bob, claim an unassigned item | Item shows Bob as assignee | US-ITEM-3 |
| TC-ITEM-4 | Reassign | As organizer, assign Bob's item to Carol | Assignee updates | US-ITEM-3 |
| TC-ITEM-5 | Delete by creator | As the item's creator (non-organizer), delete it | Succeeds | US-ITEM-4 |
| TC-ITEM-6 | Delete by organizer | As organizer, delete another member's item | Succeeds | US-ITEM-4, VIS-3 |
| TC-ITEM-7 | Delete blocked for unrelated member | As a member who didn't create the item and isn't organizer, attempt delete | No delete control / rejected | US-ITEM-4, VIS-3 |

---

## 5. Comments, Discussions & Reactions

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-COM-1 | Post root comment | As Bob, post a comment | Visible to all members immediately | US-COM-1 |
| TC-COM-2 | Reply forms a discussion | As Carol, reply to Bob's comment | Discussion view shows both; reply count updates | US-COM-2 |
| TC-COM-3 | Reply-to-reply rejected | Try to reply to Carol's reply | Blocked (two-level only) | US-COM-2 |
| TC-COM-4 | Name a discussion | As any member (not necessarily the root author), set a thread title | Title saved and shown | US-COM-3 |
| TC-COM-5 | Edit own comment | As Bob, edit his own comment body | Updated text shown | US-COM-4 |
| TC-COM-6 | Can't edit others' comments | As Carol, attempt to edit Bob's comment | No edit control / rejected | US-COM-4 |
| TC-COM-7 | Delete by author | Bob deletes his own comment | Removed for everyone | US-COM-5 |
| TC-COM-8 | Delete by organizer | Organizer deletes Carol's comment | Removed for everyone | US-COM-5, VIS-3 |
| TC-COM-9 | React and un-react | React 🎉 to a comment, then tap again | Reaction appears, then disappears (toggle) | US-COM-6 |
| TC-COM-10 | Discussion screen navigation | From the Comments tab, tap a comment that has replies | Opens the dedicated discussion screen showing the root + all replies in order | US-COM-2 |

---

## 6. Attachments

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-FILE-1 | Upload | Attach a photo or PDF | Appears in Files tab for all members | US-FILE-1 |
| TC-FILE-2 | Open | Tap to open an attachment | Opens via a working signed link | US-FILE-2 |
| TC-FILE-3 | Link expires/regenerates sanely | Open the same file after the signed-link window, or reopen later | Either a fresh link is silently issued or a clear re-fetch happens — no broken/stale link shown | US-FILE-2 |
| TC-FILE-4 | Delete by uploader | Uploader deletes their own file | Removed for everyone, storage object gone | US-FILE-3 |
| TC-FILE-5 | Delete by organizer | Organizer deletes someone else's file | Succeeds | US-FILE-3, VIS-3 |
| TC-FILE-6 | Non-member can't fetch file | Attempt to access the storage path directly as Eve | Denied | VIS-1 |

---

## 7. Polls

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-POLL-1 | Create general poll | As Bob, create a free-text poll with 2+ options | Created; visible to all members | US-POLL-1 |
| TC-POLL-2 | Create date/time/place poll | As organizer, create each of the three kinds | All three create successfully | US-POLL-2 |
| TC-POLL-3 | Non-organizer can't create date/time/place | As Bob, attempt to create a date poll | Blocked / not offered | US-POLL-2, VIS-3 |
| TC-POLL-4 | Vote and change vote | As Carol, vote, then change to a different option while open | Final vote reflected; still one vote total | US-POLL-3 |
| TC-POLL-5 | ~~Vote privacy while open~~ **RETIRED with VIS-7** | — | — | — |
| TC-POLL-6 | Close by majority | Close a poll with a clear majority | Winner recorded; for date/time/place, the event's field updates accordingly | US-POLL-4 |
| TC-POLL-7 | Close with a tie | Force a tie under majority mode and close | No winner recorded; UI communicates the tie | US-POLL-4 |
| TC-POLL-8 | Close with weighted-random | Close a wheel-mode poll | A single winner is drawn once and persists on reopen/refresh (not re-rolled) | US-POLL-4 |
| TC-POLL-9 | Non-creator can't close | As Carol, try to close Bob's poll | Blocked | US-POLL-4, VIS-3 |
| TC-POLL-10 | Reopen | As the creator, reopen a closed poll | Returns to open state and accepts votes again; existing votes stay visible to members | US-POLL-5 |
| TC-POLL-11 | Delete poll | As creator or organizer, delete a poll | Poll and its votes disappear | US-POLL-6 |

---

## 8. History

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-HIST-1 | Field edit logged | Edit the event's title | New History entry naming the field, old/new value, and actor | US-HIST-1 |
| TC-HIST-2 | Status change logged | Advance the event's phase | Entry shows the phase label (not raw key) | US-HIST-1 |
| TC-HIST-3 | Poll lifecycle logged | Create, close, and reopen a poll | Three corresponding entries appear | US-HIST-1 |
| TC-HIST-4 | No client write path | Confirm there is no "add history entry" UI anywhere | None exists | VIS-10 |

---

## 9. Expenses

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-EXP-1 | Add expense, even split | Alice pays 30, split equally among Alice/Bob/Carol | Each owes/holds 10; settle-up shows Bob→Alice 10, Carol→Alice 10 | US-EXP-1, US-EXP-2 |
| TC-EXP-2 | Add expense, uneven split | Pay 100 split 3 ways | Shares sum exactly to 100 (remainder on the last participant) | US-EXP-1 |
| TC-EXP-3 | Participants default to all members | Open the add-expense form | Every current member is pre-checked | US-EXP-1 |
| TC-EXP-4 | Deselect a participant | Uncheck one member before submitting | That member is excluded from the split and the settle-up math | US-EXP-1 |
| TC-EXP-5 | Settle-up updates live | Add a second expense that reverses part of the balance | Settle-up numbers update without manual refresh | US-EXP-2 |
| TC-EXP-6 | Fully settled state | Bring all balances to net zero | "All settled up" empty state shown, zero transfer rows | US-EXP-2 |
| TC-EXP-7 | Delete by creator | Creator deletes their own expense | Removed; settle-up recalculates | US-EXP-3 |
| TC-EXP-8 | Delete by organizer | Organizer deletes someone else's expense | Succeeds | US-EXP-3, VIS-3 |
| TC-EXP-9 | Delete blocked for unrelated member | A member who isn't the creator or organizer attempts delete | No control / rejected | US-EXP-3, VIS-3 |
| TC-EXP-10 | No edit, no mark-as-paid | Confirm neither control exists anywhere on an expense or a settle-up row | Neither exists (delete + re-add is the only correction path) | US-EXP-1/2/3 (out of scope note) |
| TC-EXP-11 | Non-member excluded | Covered fully in TC-VIS-3 applied to the Expenses panel | Dave can't open it at all | VIS-1 |

---

## 10. Friends

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-FRD-1 | Add by handle | Add Bob by `nickname#tagline` | Bob appears in Alice's list; Alice appears in Bob's (mutual, no accept) | US-FRD-1 |
| TC-FRD-2 | Add unknown handle | Try a handle that doesn't exist | Clear error | US-FRD-1 |
| TC-FRD-3 | Add yourself | Try your own handle | Rejected | US-FRD-1 |
| TC-FRD-4 | Remove friend | Covered fully in TC-VIS-9 | — | VIS-4, US-FRD-2 |

---

## 11. Groups

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-GRP-1 | Create group | Create a private group, add Bob and Carol | Group created with both members | US-GRP-1 |
| TC-GRP-2 | Rename/delete group | Rename, then delete the group | Both succeed; deleting doesn't remove the friends themselves | US-GRP-2 |
| TC-GRP-3 | Group members blind to each other | Covered fully in TC-VIS-10 | — | VIS-5 |
| TC-CREW-1 | ~~Create crew~~ **RETIRED with VIS-6** | — | — | — |
| TC-CREW-2 | ~~All members see roster~~ **RETIRED with VIS-6** | — | — | — |
| TC-CREW-3 | Only owner writes | As a non-owner crew member, attempt to add/remove someone | Blocked | US-CREW-2, VIS-6 |
| TC-CREW-4 | Rename/delete crew | Rename, then delete the crew | Both succeed; all members lose access | US-CREW-2 |

---

## 12. Notifications

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-NOTIF-1 | Friend-added notification | Alice adds Bob as a friend | Bob receives a friend-added notification | US-NOTIF-1 |
| TC-NOTIF-2 | Crew-added notification | Add Dave to a crew | Dave receives a crew-added notification | US-NOTIF-1 |
| TC-NOTIF-3 | Event-member-added notification | Add Bob to an event | Bob receives an event-member-added notification; the organizer who added him does not self-notify | US-NOTIF-1 |
| TC-NOTIF-4 | Event-confirmed notification | Advance an event to confirmed | All other members notified once; the actor doesn't self-notify; advancing further doesn't re-fire it | US-NOTIF-2 |
| TC-NOTIF-5 | Event-cancelled notification | Cancel an event | All other members notified | US-NOTIF-2 |
| TC-NOTIF-6 | Mark all read | Open notifications, mark all read | Unread count drops to zero | US-NOTIF-3 |
| TC-NOTIF-7 | Non-member excluded | Covered fully in TC-VIS-17 | — | VIS-9 |

---

## 13. Home Activity Feed

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-HOME-1 | Feed shows recent comments/items | Post a comment and add an item on an event you're in | Both appear in the Home feed | US-HOME-1 |
| TC-HOME-2 | Feed excludes invisible events | Confirm nothing from an event you are not a member of appears | Nothing appears | US-HOME-1, VIS-1 |

---

## 14. Profile & Settings

| # | Test | Steps | Expected | Story |
|---|------|-------|----------|-------|
| TC-PROF-1 | View own profile | Open Profile | Handle and avatar shown correctly | US-PROF-1 |
| TC-SET-1 | Switch language | Change to French, then Tunisian, then back to English | UI text updates fully each time, no missing/fallback strings | US-SET-1 |
| TC-SET-2 | Sign out from Settings | Covered fully in TC-AUTH-4 | — | US-SET-2 |
| TC-SET-3 | Debug account switcher (dev builds only) | Open Settings on a debug build, switch to another seeded test account | Signs out of the current account and into the chosen one without manually re-entering credentials; confirm this control is absent/disabled in a release build | (dev tooling, no story id) |

---

## Coverage notes

- This plan intentionally does **not** re-test what `rls_tests.sql` already
  proves at the database level (e.g. the exact RLS predicate on each table).
  It tests that the **UI surfaces and respects** that behavior — if a case
  here fails while `rls_tests.sql` passes, the bug is in the client, not the
  schema.
- When a new feature is added, add its stories to `SPEC.md` §<n> first, get
  it reviewed/frozen, then add its test cases here in the matching section
  before considering the feature done.
