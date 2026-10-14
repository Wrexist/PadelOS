# Architecture

PadelOS is a native SwiftUI app for iPhone with a native watchOS companion. All business
logic lives in one Swift package, **PadelKit**, shared by both apps and tested on macOS
and Linux. The apps are thin UI layers.

```
PadelOS/
├── project.yml                 XcodeGen spec (source of truth for PadelOS.xcodeproj)
├── PadelOS.xcodeproj           Generated; committed so the project opens directly
├── Packages/PadelKit/          Shared Swift package (Swift 6 language mode)
│   ├── Sources/PadelCore/      Domain: models, formats, scheduling, scoring, standings
│   ├── Sources/PadelSync/      iPhone ⇄ Watch protocol, watch outbox, transports
│   ├── Sources/PadelStore/     Persistence, observable stores, creation-form model
│   └── Tests/                  Swift Testing suites (94 tests)
├── Apps/
│   ├── Shared/                 Design tokens + display formatting (both apps)
│   ├── iOS/                    iPhone app (App, DesignSystem, Features/*)
│   ├── iOSWidget/              iPhone widget extension: the match Live Activity
│   ├── LiveActivityShared/     ActivityKit attributes + Lock Screen App Intents
│   ├── Watch/                  watchOS app (App, Views, App Intent)
│   ├── WatchWidget/            watchOS complication (WidgetKit extension)
│   ├── WatchShared/            Snapshot type shared by watch app and complication
│   └── iOSUITests/             XCUITest organiser journey
└── .github/workflows/ci.yml    Linux + macOS CI (builds, tests, screenshots)
```

## Layers

| Layer | Depends on | Responsibility |
| --- | --- | --- |
| `PadelCore` | Foundation | Pure, deterministic domain. No clocks, no randomness except seeded. |
| `PadelSync` | PadelCore | Message types, codec, watch outbox state machine, transport protocol, WatchConnectivity adapter (`#if canImport`). |
| `PadelStore` | Core, Sync | JSON persistence, `TournamentStore` (iPhone authority), `SettingsStore`, `PhoneSyncCoordinator`, `WatchStore`, `TournamentDraftModel`. All `@MainActor @Observable`. |
| Apps | all three | SwiftUI views. Views call store commands; they never mutate domain state directly. |

Dependencies are explicit: `AppModel` (iPhone) and `WatchModel` (watch) build the stores
and inject them through the SwiftUI environment. No global mutable singletons hold domain
state (the only shared object is `WatchRouter`, a navigation request counter used by the
App Intent).

## Domain model (PadelCore)

- `Tournament` is the aggregate root and the unit of persistence: configuration, players,
  teams, rounds, matches, withdrawals, status, a monotonic `revision`.
- `Match.log` (an append-only list of `ScoreEvent`s) is the **authoritative** score
  history. `Match.score/status` are a cache rebuilt by `ScoringEngine.replay` and
  re-verified on load (`repairCaches`).
- Typed IDs (`Identifier<Tag>`) prevent mixing player, match, event IDs.
- `EngineContext` injects time, device ID and an ID generator, so every operation is
  deterministic under test.

### Scoring

`ScoringEngine.apply` is the single scoring operation used for local taps, manual
entries and remote (watch) events:

1. Deduplicate by event ID (applied *or* previously rejected).
2. Validate against the rules (`ScoringRule.totalPoints(n)` or `.timed(minutes:)`) and
   the current state.
3. Append and replay the log to recompute the cache.

Event kinds: `point(side)`, `undo(eventID)`, `setScore`, `finish`, `reopen`. Undo
references the exact event it reverses and is rejected when superseded by a later
correction. Remote events that fail validation become `ScoreConflict`s stored on the
match (or on the tournament if the match no longer exists) — never silently dropped.

### Games and sets

`ScoringRule.sets(SetsRules)` adds traditional scoring next to rally points and timed
matches. `SetsRules` covers sets to win (1 or best of 3), games per set (6, or 4 for
short sets), golden point or advantage, tie-break at games-all (to 7, win by 2) and an
optional match tie-break to 10 as the decider. Presets: one set, short set to 4, best of
three with super tie-break, best of three.

The event log stays the same (`point(side)` events), so undo, deduplication, watch
offline scoring and conflicts work unchanged; `ScoringEngine.replay` folds points through
`SetsState` (points → games → sets) and caches it on the match (`Match.sets`).
`Match.score` holds games won, which is what standings count as "points" for these
tournaments, while wins are decided by sets (`ScoringEngine.winner(of:)`) — a team can
win the match with fewer games. Manual results are entered set by set (`setSets`) and
must form a legal, complete match (`SetsRules.isLegalSetScore`, e.g. 7–5, 7–6, [10–8]).

### Scheduling

Hard constraints (never traded for fairness): each player at most once per round, valid
team composition (two players; one of each group for Mixed; registered team for Team
Americano), court capacity respected, completed/started rounds never rewritten.

Soft objective, in priority order (lower is better):

```
1000 × partner repeats  (team format: opponent repeats)
+ 300 × consecutive rests
+  10 × Σ(times opposed)²            (spreads opponents evenly)
```

| Format | Method |
| --- | --- |
| Americano / Mixed | Per round: fair rest selection, then steepest-descent pair-swap search over 8 seeded restarts (`DoublesOptimizer`, cost `100·c²` per partnership, `8·c²` per opposing pair). Whole schedule: best of K seeded candidates (K = 4…24 by size). Mixed swaps only within a group, so every team is one A + one B. |
| Team Americano | Circle method (perfect round robin) when all teams fit on court; otherwise the better of a round-robin queue and history-aware local search. |
| Mexicano | Round 1 seeded draw or list order. Later rounds: standings from completed rounds only; blocks of four by rank, pattern 1&4 v 2&3 (configurable); a local search may use another pattern (+15) or swap players between adjacent blocks (+25 per displaced player) to avoid repeat partners (+100·c²) / opponents (+5·c²). Generated one round at a time, only when every previous round is complete. |
| Mixicano | Mexicano with groups: each group is ranked separately; court g takes the g-th pair of each group; teams are strongest A + weaker B v weaker A + strongest B (+15 for the other pairing); A↔A and B↔B swaps between neighbouring courts avoid repeats. |
| Team Mexicano | Fixed teams ranked by team standings: 1 v 2, 3 v 4, …; swaps between neighbouring courts (+25, plus a small rank-based amount so the leader keeps court 1) avoid repeat meetings (+100·c²). |
| King of the Court | Court ladder: winners move up a court, losers move down (court 1 winners and bottom-court losers stay; a draw keeps both teams in place). On each court the arriving winners are split up and partnered with arriving losers; players back from a rest join the bottom court. |
| Swiss | Fixed teams, standings-driven like Team Mexicano, but ranked wins first (wins → total points → head-to-head → point difference) and repeat meetings avoided. Recommended rounds: ⌈log₂ T⌉ + 1. |
| Final round (optional) | Standings-based: court 1 = ranks 1–4 (1&4 v 2&3); teams 1 v 2. Lowest-ranked rest. |
| Playoffs (optional) | Knockout stage after the regular rounds: final (top 2), semifinals (top 4) or quarterfinals (top 8). See below. |

Rest rule: those who have **played the most** rest first (so max − min played ≤ 1 for
everyone present since round 1, and late joiners are not benched again), then avoid
consecutive rests, then seeded order. All randomness is SplitMix64 seeded from the
tournament seed and round number, so a saved schedule is reproducible and regenerating
unplayed rounds is stable.

These are heuristics, not proven optima. Quality is measured in tests: on every reference
configuration (4–24 players, 1–6 courts, 3–15 rounds) partner repeats equal the
theoretical minimum, and 8 players/2 courts/7 rounds yields the perfect schedule (every
pair partners once, opposes twice).

### Knockout playoffs

`TournamentConfiguration.playoff` (`PlayoffSize`) appends 1–3 knockout rounds
(`RoundKind.knockout`); `totalRoundCount = roundCount + playoff.stageCount`. They are
planned lazily like Mexicano rounds:

- The first stage is seeded from the regular standings in bracket order (1 v 8, 4 v 5,
  2 v 7, 3 v 6). Fixed-team formats seed teams; individual formats first form pairs
  (seed *i* with seed 2n+1−*i*; with groups, A *i* with B n−1−*i*) so pairs are balanced.
- Later stages pair the winners in bracket order once the previous stage is complete.
- A knockout match needs a winner: an even points total becomes odd for knockout matches
  (`scoringRule(for:)`), and finishing a tied timed match is refused
  (`ScoreRejection.drawNotAllowed`).
- Knockout rounds never count towards the standings; `playoffChampion` /
  `playoffRunnerUp` come from the final. The playoff size can only change before the
  first knockout round starts.

### Standings

Derived, never stored: `StandingsCalculator.compute` rebuilds from completed matches.

- Individual formats: total points → wins → point difference → shared rank.
- Team Americano: total points → wins → head-to-head points (exactly two tied teams) →
  point difference → shared rank.
- Optional rest compensation (half the match total per completed rest round).
- Competition ranking (1, 2, 2, 4) with an `isTied` flag shown as "=2".

### Lifecycle

`Tournament.reconcileRounds` keeps standings-based rounds consistent: an unstarted
Mexicano/final round is removed if an earlier round becomes incomplete (reopen) or an
earlier result is corrected, and is regenerated once all prior rounds are complete.
`regenerateFutureRounds` (withdrawals, late players, court/round changes) keeps every
round with a started match and rebuilds the rest from history.

## Persistence

- One JSON file per tournament (`Application Support/Tournaments/<id>.json`), written
  atomically (temp file + rename). Envelope: `{schemaVersion, savedAt, value}`.
- `TournamentSchema.migrate` is the upgrade hook; files from a newer app version are
  reported and left untouched; damaged files are moved to `Quarantine/` and reported.
- `TournamentStore.perform` is a transaction: copy → domain operation → save → publish.
  If validation or saving fails, the visible state is unchanged.
- Settings use tolerant decoding (missing keys get defaults) — no migration needed to add
  a setting.

SwiftData was considered and not used: the aggregate is a document whose integrity
depends on replaying an event log; per-tournament atomic JSON gives explicit
transactions, trivial migrations, identical behaviour on iPhone, watch and Linux CI, and
no Core Data threading rules. Sizes are small (a large tournament is < 200 KB).

## iPhone ⇄ Watch synchronisation

The iPhone is the authority. The watch scores offline optimistically.

```
Watch                                   iPhone
─────                                   ──────
tap +1 → validate on local view
       → append to outbox, save file
       → send cumulative EventBatch ──►  applyRemoteEvents (dedupe, validate,
         • sendMessage when reachable     conflicts kept) → save → snapshot
         • else transferUserInfo,     ◄── WatchSnapshot via reply (if reachable)
           replacing older transfers       and updateApplicationContext (always)
receive snapshot (newer sequence only)
  → drop outbox events it acknowledges
  → replay remaining outbox on top
```

- **Durability**: an event leaves the watch outbox only when a snapshot *generated after
  the iPhone saved* acknowledges it (listed in `acknowledgedEventIDs` or present in a
  match log/conflict). Message delivery alone is never treated as persistence.
- **Duplicates / reordering**: event IDs make application idempotent; per-device
  sequence numbers order a batch; batches are cumulative, so a lost or late batch is
  harmless.
- **Stale snapshots**: ignored unless their sequence is higher (sequence persisted on the
  iPhone; a new iPhone installation is recognised by `phoneInstanceID`).
- **Conflicts**: watch events invalid on the iPhone (e.g. match already finished there)
  are stored as conflicts, acknowledged, and shown on the iPhone for review.
- **Round generation** happens only on the iPhone, so the two devices can never create
  competing Mexicano rounds. Precomputed schedules (Americano, Mixed, Team) let the watch
  move to the next round offline.
- Snapshot payloads are compacted (no event history for finished matches of earlier
  rounds) and capped near 48 KB.

## Live Activity (iPhone)

- `PadelOSWidgets` (iOS widget extension) draws `MatchActivityAttributes`: Lock Screen
  card (court, round, both teams, big score, progress, +1 A / undo / +1 B) and Dynamic
  Island (compact scores, expanded view with buttons).
- Started when a match is opened for scoring (setting "Live Activity on Lock Screen", on
  by default), one activity at a time. `LiveActivityController` observes the store, so
  points from the app, the Lock Screen and the Apple Watch all update it; finished
  matches end it (kept visible for 15 minutes).
- The buttons are `LiveActivityIntent`s, which run in the app's process: they load the
  store if needed (`AppModel.shared`), record the point through the same transaction as
  an in-app tap, then push the new state. The extension compiles the intent types only
  to draw the buttons (`WIDGET_EXTENSION` condition).
- Content is computed by `LiveMatchSummary` in PadelCore (unit-tested): points or game
  points, games/sets line, situation (deuce, golden point, tie-break), progress.
- Local updates only (no push notifications or server), so the activity updates while
  the app or its intents are running — which is whenever someone scores.

## Apple Watch app

- Single-target watchOS app (`WKApplication`), embedded in the iPhone app.
- Main screen: two large tap targets (Team A lime, Team B graphite) showing names and
  score; undo and an actions sheet below; finishing requires confirmation. Dims in
  Always On (`isLuminanceReduced`). Haptics via `WKInterfaceDevice`.
- `OpenActiveMatchIntent` + `AppShortcutsProvider`: lets the wearer bind the Apple Watch
  Ultra Action button (via a Shortcut) or Siri to open the active match. The app does not
  and cannot intercept the Action button directly.
- Complication (`Apps/WatchWidget`, WidgetKit accessory families: rectangular, circular
  gauge, corner, inline) shows the active court and score; tapping opens the app. The
  watch app writes a tiny `ActiveMatchSnapshot` to the App Group `group.app.padelos` and
  reloads timelines only when it changes (no polling, `.never` refresh policy). Without
  the App Group entitlement (unsigned builds) it shows a placeholder; scoring never
  depends on it.

## Onboarding

`OnboardingView` (iPhone) is shown once on first launch (`AppSettings.hasCompletedOnboarding`,
decoded tolerantly so older settings files keep working) and again from Settings → Show
introduction. Five pages with native SwiftUI illustrations — a court that draws itself and
a bouncing ball (`keyframeAnimator`), players rotating partners (`PhaseAnimator`), a watch
being tapped, the Dynamic Island expanding, and a checklist — plus staggered text reveals,
a drifting background glow and a stretching page indicator. With Reduce Motion every
animation is replaced by a static frame or a short cross-fade. UI tests skip it unless
they pass `-show-onboarding`.

## Localization

The apps ship in 19 languages: English (source), Spanish, Catalan, Portuguese (Portugal
and Brazil), French, Italian, German, Dutch, Swedish, Danish, Norwegian Bokmål, Finnish,
Polish, Czech, Russian, Arabic (right-to-left), Japanese and Simplified Chinese.

- App code uses `String(localized:)` and SwiftUI's `LocalizedStringKey` literals, so the
  compiler extracts every string. Components that take titles (`SectionHeader`,
  `EmptyStateView`, `ValueRow`) accept `LocalizedStringKey`; already-localized text goes
  through a disfavoured `String` overload.
- Text produced by the shared package (validation messages, score rejections, share
  summaries, Live Activity labels, format names) goes through `L10n.string` /
  `L10n.format`, which look the English key up in the app bundle. On Linux and in tests
  the key itself is returned, so tests read English.
- Numbers use printf placeholders (`%lld`, `%@`); count strings have CLDR plural
  variations (Arabic uses all six forms; Polish, Czech and Russian one/few/many/other).
  Multi-argument strings avoid plural agreement, and translations reorder arguments with
  positional placeholders where needed.
- Pipeline: CI exports the extracted keys (`xcodebuild -exportLocalizations`);
  `Localization/source-strings.json` holds the source keys with translator notes;
  `Localization/translations/<lang>.json` holds the translations;
  `scripts/check_translation.py` validates placeholders, plural forms and line breaks;
  `scripts/build_string_catalogs.py` writes `Localizable.xcstrings` for the iPhone app,
  watch app and both widget extensions. CI fails if a catalog is out of date.
- Weekday-based default tournament names use the device locale. App Shortcut phrases
  (Siri) are still English only.
