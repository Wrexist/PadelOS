# Testing

## Automated tests

### Shared package (PadelKit) — Swift Testing, runs on macOS and Linux

```sh
swift test --package-path Packages/PadelKit
```

| Suite | What it proves |
| --- | --- |
| Scheduling | Hard invariants (no double booking, valid teams, court capacity) on 12 reference Americano configurations (4–24 players, odd counts, more players than courts) and 40 randomised configurations (recorded seed `2026`); partner repeats equal the theoretical minimum; played/rest spread ≤ 1; no consecutive rests; 8-player perfect whist schedule; same seed ⇒ identical schedule; Mixed one-per-group teams; Team round robin with no premature repeats; performance bound. |
| Mexicano | Lazy round generation; standings-based grouping (1&4 v 2&3); repeat avoidance; deterministic tie handling; completed rounds never rewritten; corrections rebuild only unstarted rounds; reopen removes dependent round; in-progress results ignored; list-order first round. |
| Final round | Americano, Team and Mixed standings-based finals. |
| Scoring | Increments, total cap, finish rules, draws, multiple undo, undo of corrections, undo after finish, manual score validation, corrections (reopen/set/finish), timed matches, replay = cache under random sequences, deduplication, out-of-order remote events, conflicts recorded, orphaned events, superseded undo, finished tournament is read-only. |
| Standings | Individual credit, full tie-break chain with shared ranks, team standings and head-to-head, rest compensation, reproducible from saved JSON, withdrawn players, share summary text. |
| Validation | Player counts/names, capacity warnings with alternatives, Mixed group rules, team rules, numeric ranges, round planner. |
| Tournament management | Withdrawal (keeps history, reschedules), refused withdrawals, late joiner, team withdrawal/addition, settings edits, restart (same/new seed), finish/reopen, revision monotonicity, watch projection, Codable round trip for all formats. |
| Sync | iPhone→watch, watch→iPhone, offline + reconnect, duplicate delivery, out-of-order batches, stale snapshots, new phone installation, watch restart with pending events (and a lost transfer), conflicting edits, save failure not acknowledged, Mexicano next round from watch, deleted tournament, watch-side validation, snapshot size, codec versioning, randomised drop/duplicate/reorder convergence (seed `4242`). |
| Persistence | Survives restart, damaged file quarantined, newer schema untouched, cache repair from log, failed save leaves state unchanged, domain errors not saved, tolerant settings decoding, monotonic sync sequence. |
| Journey | Create → score → undo → finish → standings → "restart app" → resume → correct → finish tournament → share text, against real files. |
| Create form | Name entry, paste lists (with numbering/bullets), duplicates, team pairing, Mixed groups, reordering, quick start, timed rules. |

Randomised tests print/record their seeds so failures are reproducible.

### iPhone UI tests (XCUITest)

`Apps/iOSUITests/OrganiserJourneyUITests.swift`, run with the `PadelOS` scheme:

```sh
xcodebuild test -project PadelOS.xcodeproj -scheme PadelOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Covers: create tournament, add players, generate schedule, start a match, register
points, undo, finish via result entry, verify standings, terminate and relaunch, resume,
correct a result, share button availability; invalid configuration explanation; basic
accessibility (labels/identifiers, hittable controls). The app runs with `-ui-testing
-reset-data`, which stores data in a temporary folder. Screenshots are attached to the
result bundle.

### CI

`.github/workflows/ci.yml` runs on every push:

1. Linux (`swift:6.2` container): package tests.
2. macOS: package tests, watchOS build, iOS build (verifies the watch app is embedded),
   UI tests on an iPhone simulator, screenshots exported from the result bundle, and a
   watch screenshot of the scoring screen on an Apple Watch Ultra simulator
   (`-demo-scoring` launch argument). Artifacts: `screenshots-and-logs`.

## Manual / device testing still required

Simulators cannot prove these; they need a paired iPhone + Apple Watch (ideally Ultra):

1. Install from Xcode with your team set (Signing & Capabilities for both targets).
2. Create a tournament on iPhone → it appears on the watch within seconds (app context).
3. Score points on the watch with the iPhone nearby → iPhone updates live.
4. Enable Airplane Mode on the watch (or walk out of range), score 10+ points, undo once,
   force-quit the watch app, relaunch → pending count shown, score intact.
5. Reconnect → pending count drops to zero; iPhone shows the same score.
6. While disconnected, finish the same match on the iPhone with a different score, then
   reconnect → iPhone keeps its result and shows "score changes from Apple Watch could
   not be applied" with a review list.
7. Mexicano: finish the last match of a round on the watch → the next round appears on
   the watch after the iPhone draws it.
8. Shortcuts: create a shortcut running "Open Active Match", assign it to the Ultra
   Action button, press it → the scoring screen opens.
9. Check Always On dimming, haptics, and VoiceOver on both devices; Dynamic Type at the
   largest accessibility sizes on iPhone.
