# Implementation plan

Status legend: ✅ done and verified by automated tests/builds · 🟡 implemented, needs
device verification · ⏭ deliberately deferred.

## Phase A — Audit and foundation ✅
- Repository contained only a design mockup (`docs/design/reference-mockup.png`); no
  existing code to preserve.
- Environment: Linux container, no Xcode. Installed Swift 6.2.1 for Linux to build/test
  the shared package; built XcodeGen 2.44.1 to generate the Xcode project; Apple builds
  run on GitHub Actions macOS runners (public repository).
- Architecture: one shared package (Core/Sync/Store) + thin SwiftUI apps.

## Phase B — Tournament engine ✅
- Scoring events, replay, undo, corrections, conflicts, deduplication.
- Standings with explicit tie-breakers (individual vs team).
- Americano, Mixed Americano, Team Americano, Mexicano, optional final round.
- Validation with plain-language messages and suggestions.
- Fairness metrics and reproducibility tests.

## Phase C — iPhone app ✅ (builds and UI tests in CI)
- Home, creation flow (format, players incl. paste/recent names, courts, points,
  rounds auto/manual with duration estimate, advanced options), tournament dashboard
  (Live/Schedule/Standings), scoring, result entry/correction, standings detail,
  management (rename, courts/rounds, final round, rest points, withdraw/add players or
  teams, finish/reopen/restart/delete, fairness), conflict review, sharing (rendered
  card + text), settings.

## Phase D — Apple Watch 🟡
- Native watchOS app: home, courts, standings, scoring, actions, finished screen.
- Offline outbox, persistence, WatchConnectivity transport, sync status.
- App Intent / App Shortcut to open the active match (Action button via Shortcuts).
- Complication showing the active court and score (WidgetKit, App Group).
- Needs physical-device verification of WatchConnectivity behaviour.

## Phase E — Integration ✅ (simulated) / 🟡 (devices)
- End-to-end sync tests over an in-memory transport with drops, duplicates, reordering,
  restarts and save failures.

## Phase F — Quality and release readiness
- CI on Linux and macOS, screenshots captured for visual review.
- Documentation (this file, README, ARCHITECTURE, TESTING, PROJECT_STATUS).
- Release checklist (remaining, needs the owner): signing team, App Store Connect record,
  privacy nutrition label ("Data Not Collected"), screenshots, TestFlight.

## Phase G — Post-MVP additions
- ✅ Traditional games/sets scoring (golden point/advantage, tie-breaks, super tie-break,
  short sets), on iPhone, Apple Watch and in result entry.
- ✅ New formats: Mixicano, Team Mexicano, King of the Court.
- 🟡 Live Activity with Lock Screen / Dynamic Island scoring (builds and starts in the
  simulator; Lock Screen buttons need device verification).

## Roadmap
- ⏭ Swiss, playoffs/elimination brackets.
- ⏭ Cloud sync and public live leaderboard (needs a backend and accounts).
- ⏭ Player profiles across tournaments, history statistics.
