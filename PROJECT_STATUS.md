# Project status

_Last updated: 2026-10-14 · branch `claude/padel-mvp`_

## Starting point

The repository contained only a design mockup (now `docs/design/reference-mockup.png`).
Everything else was built in this branch.

## Environment used

- Development container: Linux (Ubuntu 24.04), **no Xcode**. Swift 6.2.1 for Linux was
  installed to build and test the shared package; XcodeGen 2.44.1 was built from source
  to generate `PadelOS.xcodeproj`.
- Apple builds and simulator tests run on **GitHub Actions macOS runners** (`macos-15`,
  Xcode 26.3, iOS 26.2 / watchOS simulators). The repository is public, so these runners
  are free.
- No physical iPhone or Apple Watch was available.

## Verification matrix

| Area | Implemented | Automated tests | Verified how |
| --- | --- | --- | --- |
| Domain engine (4 formats, final round, validation) | ✅ | ✅ 96 package tests | Linux (local + CI) and macOS CI |
| Scoring, undo, corrections, conflicts, dedup | ✅ | ✅ | Linux + macOS CI |
| Standings and tie-breakers | ✅ | ✅ | Linux + macOS CI |
| Persistence, migration hook, quarantine, atomicity | ✅ | ✅ | Linux + macOS CI (real files) |
| Sync protocol (outbox, acks, stale, conflicts) | ✅ | ✅ simulated transport | Linux + macOS CI |
| iPhone app builds | ✅ | — | CI: `BUILD SUCCEEDED`, 0 Swift warnings |
| watchOS app + complication build | ✅ | — | CI: `BUILD SUCCEEDED`, watch app embedded in iPhone app |
| iPhone organiser journey | ✅ | ✅ 3 XCUITests | CI run #5 on iPhone 16 Pro (iOS 26.2) simulator: 3 passed, 0 failed (light); full journey re-run in dark mode: passed |
| iPhone visuals | ✅ | screenshots | Reviewed CI screenshots in light and dark mode (`docs/screenshots/`) |
| Watch scoring UI | ✅ | screenshot | Apple Watch Ultra 3 (49 mm) simulator screenshot of the scoring screen and home |
| WatchConnectivity on real devices | ✅ code | ❌ | **Not verified** — needs paired hardware (see TESTING.md checklist) |
| Complication on a watch face | ✅ code | ❌ | Builds; **not verified** on device (needs signing + App Group) |
| Action button via Shortcuts (App Intent) | ✅ code | ❌ | Builds; **not verified** on device |
| Haptics, Always On dimming | ✅ code | ❌ | Not verifiable in CI |

## Known limitations / open items

- Device-only behaviour (WatchConnectivity timing, background delivery, complication
  refresh, haptics, Action button) is implemented against Apple's documented APIs but
  untested on hardware.
- Signing: `DEVELOPMENT_TEAM` is empty. Set your team for the three targets; the App
  Group `group.app.padelos` must be enabled (Xcode does this automatically with
  automatic signing when the team has App Groups available).
- Scheduling is heuristic (documented objective, measured in tests). It reaches the
  theoretical minimum partner repeats on all reference configurations, but optimality is
  not proven for arbitrary inputs.
- Traditional games/sets scoring is intentionally not offered.
- A withdrawal takes effect from the first round with no started match; a withdrawn
  player's unstarted match inside a round already in progress stays (enter a result or
  leave it unplayed).
- Schedule generation runs on the main thread. Measured with an optimised build on the
  Linux container: all 12 reference Americano schedules (4–24 players, up to 15 rounds)
  generate in 0.4 s in total, so a single tournament takes tens of milliseconds. Debug
  builds are roughly 10× slower.

## How to reproduce the verification

```sh
swift test --package-path Packages/PadelKit             # 96 tests
xcodebuild -project PadelOS.xcodeproj -scheme PadelOSWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PadelOS.xcodeproj -scheme PadelOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test
```
