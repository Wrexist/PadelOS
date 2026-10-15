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
| Domain engine (8 formats, final round, playoffs, validation) | ✅ | ✅ 136 package tests | Linux (local + CI) and macOS CI |
| Games and sets scoring (golden point/advantage, tie-breaks, super tie-break) | ✅ | ✅ incl. randomised replay | Linux + macOS CI |
| New formats: Mixicano, Team Mexicano, King of the Court, Swiss | ✅ | ✅ | Linux + macOS CI |
| Knockout playoffs (final / semifinals / quarterfinals) | ✅ | ✅ seeding, advancement, no draws, standings excluded | Linux + macOS CI; bracket UI test + screenshot (`docs/screenshots/playoffs.png`) |
| Scoring, undo, corrections, conflicts, dedup | ✅ | ✅ | Linux + macOS CI |
| Standings and tie-breakers | ✅ | ✅ | Linux + macOS CI |
| Persistence, migration hook, quarantine, atomicity | ✅ | ✅ | Linux + macOS CI (real files) |
| Sync protocol (outbox, acks, stale, conflicts) | ✅ | ✅ simulated transport | Linux + macOS CI |
| iPhone app + Live Activity extension builds | ✅ | — | CI: `BUILD SUCCEEDED`, 0 warnings |
| watchOS app + complication build | ✅ | — | CI: `BUILD SUCCEEDED`, watch app embedded in iPhone app |
| iPhone UI tests | ✅ | ✅ 8 XCUITests | CI run #28 on an iPhone 16 Pro simulator: 8 passed, 0 failed (journey, games & sets scoring + set entry, Live Activity, validation, accessibility, onboarding, onboarding skip, playoff bracket); journey re-run in dark mode: passed |
| Onboarding | ✅ | ✅ 2 UI tests | Screenshots of all five pages reviewed (`docs/screenshots/onboarding.png`); Reduce Motion path implemented, not screenshot-tested |
| Localization (19 languages) | ✅ | ✅ placeholder/plural/line-break checks for 18 translations; catalogs checked up to date | CI run #28: onboarding + playoff UI tests passed in Spanish, Arabic (right-to-left) and Swedish; screenshots reviewed (`docs/screenshots/languages.png`). Other languages build and are checked automatically but were not screenshot-reviewed |
| Live Activity | ✅ | ✅ starts + updates | Simulator: Dynamic Island shows the live score after leaving the app (`docs/screenshots/sets-and-live-activity.png`) |
| Lock Screen +1/undo buttons | ✅ code | ❌ | Builds; tapping them needs a device (not automatable in CI) |
| iPhone visuals | ✅ | screenshots | Reviewed CI screenshots in light and dark mode (`docs/screenshots/`) |
| Watch scoring UI | ✅ | screenshot | Apple Watch Ultra 3 (49 mm) simulator screenshot of the scoring screen and home |
| WatchConnectivity on real devices | ✅ code | ❌ | **Not verified** — needs paired hardware (see TESTING.md checklist) |
| Complication on a watch face | ✅ code | ❌ | Builds; **not verified** on device (needs signing + App Group) |
| Action button via Shortcuts (App Intent) | ✅ code | ❌ | Builds; **not verified** on device |
| Haptics, Always On dimming | ✅ code | ❌ | Not verifiable in CI |
| Privacy manifests (iPhone, watch, complication) | ✅ | ✅ `check-release.mjs` | Generated project bundles each one in its own target |
| TestFlight pipeline (CI + local) | ✅ | ✅ tooling selftest | **Not run against Apple yet** — needs secrets and the app record (`docs/RELEASE.md`) |

## Known limitations / open items

- Translations were produced with AI assistance and validated automatically
  (placeholders, plural categories, line breaks) and visually in Spanish, Arabic and
  Swedish. A native-speaker review is recommended before release. Siri / App Shortcut
  phrases are English only.

- Device-only behaviour (WatchConnectivity timing, background delivery, complication
  refresh, haptics, Action button) is implemented against Apple's documented APIs but
  untested on hardware.
- Signing and TestFlight: `DEVELOPMENT_TEAM` is set to `S3U8B8HH96`. The release
  pipeline (`docs/RELEASE.md`) is written but **not yet run**: it needs the App Store
  Connect app record and the API key secrets in this repository. Its offline parts
  (selftest, bundle rules, project regeneration, workflow lint) pass on Linux.
- Scheduling is heuristic (documented objective, measured in tests). It reaches the
  theoretical minimum partner repeats on all reference configurations, but optimality is
  not proven for arbitrary inputs.
- A withdrawal takes effect from the first round with no started match; a withdrawn
  player's unstarted match inside a round already in progress stays (enter a result or
  leave it unplayed).
- Schedule generation runs on the main thread. Measured with an optimised build on the
  Linux container: all 12 reference Americano schedules (4–24 players, up to 15 rounds)
  generate in 0.4 s in total, so a single tournament takes tens of milliseconds. Debug
  builds are roughly 10× slower.

## How to reproduce the verification

```sh
swift test --package-path Packages/PadelKit             # 136 tests
python3 scripts/check_translation.py $(ls Localization/translations | sed 's/\.json$//')
python3 scripts/build_string_catalogs.py --check
xcodebuild -project PadelOS.xcodeproj -scheme PadelOSWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PadelOS.xcodeproj -scheme PadelOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO test
```
