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
| Games and sets | 15/30/40 progression, golden point, advantage/deuce, 6–4 and 7–5 sets, tie-break at 6–6, super tie-break decider, short sets, undo across a game boundary, legal/illegal entered results, standings by games with wins by sets (winning with fewer games), random rally sequences for every preset (replay = incremental, legal set scores, seed 31), fixed teams, validation. |
| New formats | Mixicano (group invariants, standings blocks, fairness), Team Mexicano (1 v 2, repeat avoidance, rests with odd team counts), King of the Court (winners up/losers down, draws stay, partners split, rests, games/sets), withdrawals/late players, standings-based finals. The randomised and reproducibility suites cover all 8 formats. |
| Live Activity content | Points/progress/finished, games-and-sets labels and situation, unknown match. |
| Playoffs and Swiss | Bracket seeding (1 v 8, 4 v 5, 2 v 7, 3 v 6), balanced pairs in individual and grouped formats, winners advance, champion/runner-up, ties refused in knockout matches, odd totals for knockout matches, knockout rounds excluded from standings, reopening a semifinal, settings changes refused after the playoffs start, validation, Swiss pairing and tie-breakers. |
| Create form | Name entry, paste lists (with numbering/bullets), duplicates, team pairing, Mixed groups, reordering, quick start, timed rules. |

Randomised tests print/record their seeds so failures are reproducible.

Translation checks (no Xcode needed):

```sh
python3 scripts/check_translation.py es ar sv   # placeholders, plural forms, line breaks
python3 scripts/build_string_catalogs.py --check
```

### iPhone UI tests (XCUITest)

`Apps/iOSUITests/OrganiserJourneyUITests.swift`, run with the `PadelOS` scheme:

```sh
xcodebuild test -project PadelOS.xcodeproj -scheme PadelOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Also: onboarding (all five pages with screenshots, then Get Started; and Skip), a
seeded playoff tournament (`-demo-playoffs`) showing the semifinals and the bracket, a
games-and-sets tournament (scoring labels 15/40/game, undo, set-by-set result
entry) and a test that leaves the app while a match is being scored and captures the
Dynamic Island with the running Live Activity.

Covers: create tournament, add players, generate schedule, start a match, register
points, undo, finish via result entry, verify standings, terminate and relaunch, resume,
correct a result, share button availability; invalid configuration explanation; basic
accessibility (labels/identifiers, hittable controls). The app runs with `-ui-testing
-reset-data`, which stores data in a temporary folder. Screenshots are attached to the
result bundle.

### CI

`.github/workflows/ci.yml` runs on pull requests and pushes to `main` (dispatch it from
the Actions tab for any other branch; Markdown/docs-only changes skip it):

1. Linux checks (gate the macOS job): release tooling selftest, App Store bundle rules
   (`scripts/release/check-release.mjs`: icons, privacy manifests, bundle ids, App Group,
   export compliance), translation and catalog checks, actionlint and shellcheck.
2. Linux (`swift:6.2` container): package tests.
3. macOS (`macos-26`, the TestFlight image): `PadelOS.xcodeproj` matches `project.yml`, package tests, watchOS build, iOS build (verifies the watch app is embedded),
   UI tests on an iPhone simulator, screenshots exported from the result bundle, and a
   watch screenshot of the scoring screen on an Apple Watch Ultra simulator
   (`-demo-scoring` launch argument). Artifacts: `screenshots-and-logs`.
4. Watch and Live Activity screenshots (`.github/workflows/watch-screens.yml`, on pull
   requests touching the watch, complication or Live Activity, or from the Actions tab):
   every watch demo scenario (`-demo-scenario home|points|deuce|golden|matchpoint|tiebreak|won|finished|standings|podium|alwayson|complications`)
   on an Apple Watch Ultra and a 41/42 mm watch, and the Dynamic Island (compact and
   expanded), Notification Center and Lock Screen from `LiveActivityGalleryUITests`
   (skipped unless `CAPTURE_LIVE_ACTIVITY=1`). Artifact: `watch-screens`.
5. Localization: string export, and the onboarding and
   playoff UI tests re-run in Spanish, Arabic (right-to-left) and Swedish with
   screenshots (`TEST_RUNNER_UITEST_LANGUAGE`).

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
7. Live Activity: open a match on the iPhone, lock the phone, tap +1 A / undo on the
   Lock Screen → the score changes on the Lock Screen and in the app; score on the
   watch → the Lock Screen follows.
8. Mexicano: finish the last match of a round on the watch → the next round appears on
   the watch after the iPhone draws it.
9. Shortcuts: create a shortcut running "Open Active Match", assign it to the Ultra
   Action button, press it → the scoring screen opens.
10. Check Always On dimming, haptics, and VoiceOver on both devices; Dynamic Type at the
   largest accessibility sizes on iPhone.
11. Watch scoring feel (Ultra and a 41 mm watch): tap each half → ball arcs to that side,
   click haptic, success haptic on a won game/set; turn the Digital Crown slowly → the
   ring around undo fills and one point is undone with "Point undone" (a small accidental
   turn must not undo, and the ring empties when you stop); deuce / golden point /
   match point banners sweep in; Always On (lower the wrist) shows the dimmed scoreboard.
12. Double Tap (Series 9+/Ultra 2+, watchOS 11): in "…" choose "+1 <team>", double-tap
   with the watch hand → that team scores; when the match is won, Double Tap opens the
   Finish confirmation; on the finished screen it goes to the next court.
13. Complication: add PadelOS to a face (rectangular, circular, corner, inline) and to the
   Smart Stack; score on the watch → it updates; check tinted/accented faces.
14. Live Activity: compact, minimal (start a second activity such as a timer), expanded
   (long-press) and Lock Screen; the numerals roll on +1, the winner gets the trophy when
   the total is reached, and the activity appears in the watch Smart Stack (watchOS 11).
15. Languages: switch the iPhone (or just PadelOS in Settings → PadelOS → Language) to a
   few languages, including Arabic, and walk through create → score → standings → share.
   Translations were produced with AI assistance and checked automatically for
   placeholders and plurals; a native speaker should review wording before release.
