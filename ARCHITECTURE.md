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
│   ├── Watch/                  watchOS app (App, Views, App Intent)
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
| Final round (optional) | Standings-based: court 1 = ranks 1–4 (1&4 v 2&3); teams 1 v 2. Lowest-ranked rest. |

Rest rule: those who have **played the most** rest first (so max − min played ≤ 1 for
everyone present since round 1, and late joiners are not benched again), then avoid
consecutive rests, then seeded order. All randomness is SplitMix64 seeded from the
tournament seed and round number, so a saved schedule is reproducible and regenerating
unplayed rounds is stable.

These are heuristics, not proven optima. Quality is measured in tests: on every reference
configuration (4–24 players, 1–6 courts, 3–15 rounds) partner repeats equal the
theoretical minimum, and 8 players/2 courts/7 rounds yields the perfect schedule (every
pair partners once, opposes twice).

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

## Apple Watch app

- Single-target watchOS app (`WKApplication`), embedded in the iPhone app.
- Main screen: two large tap targets (Team A lime, Team B graphite) showing names and
  score; undo and an actions sheet below; finishing requires confirmation. Dims in
  Always On (`isLuminanceReduced`). Haptics via `WKInterfaceDevice`.
- `OpenActiveMatchIntent` + `AppShortcutsProvider`: lets the wearer bind the Apple Watch
  Ultra Action button (via a Shortcut) or Siri to open the active match. The app does not
  and cannot intercept the Action button directly.
- No complication yet (needs an App Group shared container and signing; see roadmap).
