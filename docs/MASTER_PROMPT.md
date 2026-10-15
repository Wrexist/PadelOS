# PadelOS — master prompt: from this branch to a build on your phone

Three agents, three places, one order. Each prompt below is self-contained: copy the
fenced block into the tool named in its heading. The facts they share are in §6;
the runbook they all follow is `docs/RELEASE.md`.

| Where | Agent | What only it can do |
| --- | --- | --- |
| Your Mac | **T3 Code** (or Claude Code in a terminal) with this repo checked out | Xcode: archive, sign with your Apple ID, upload, register the bundle ids and App Group |
| Your browser | **Claude in Chrome** | Pages behind your Apple Account and 2FA: App Store Connect, the developer portal, GitHub settings |
| Cloud | **Claude Code** (claude.ai/code) | PRs, CI, dispatching and watching the TestFlight workflow, fixing what CI reports |

Secrets rule for all of them: **the .p8 key, .p12 certificate and their passwords are
typed or pasted by you, never by an agent, and never appear in a chat, commit, issue,
log or screenshot.** Agents may open the page where you paste them.

---

## 1 · Order of operations

| # | Step | Who | Prompt |
| --- | --- | --- | --- |
| 1 | Merge `claude/ios-release-pipeline` into `main` (the TestFlight workflow can only be dispatched from `main`) | Cloud | §4 part 1 |
| 2 | Archive once from the Mac with `--no-upload`: registers the four bundle ids and `group.app.padelos` | T3 Code | §2 part A |
| 3 | Create the App Store Connect app record, the internal TestFlight group, App Privacy "Data Not Collected" | Chrome | §3 parts A–C |
| 4 | Create an Admin API key; you download the .p8 | Chrome + you | §3 part D |
| 5 | Add the three GitHub secrets (you paste the values) | Chrome + you | §3 part E |
| 6 | First upload from the Mac, wait for processing, install from TestFlight | T3 Code + you | §2 part B |
| 7 | First upload from GitHub (proves the Mac-less path) and watch it to VALID | Cloud | §4 part 2 |
| 8 | Device checklist on a real iPhone + Apple Watch (TESTING.md "Manual / device testing") | You (+ T3 Code to fix) | §2 part C |

Steps 2–5 can happen in any order; 6 needs 2 and 3; 7 needs 1, 3, 4 and 5.

---

## 2 · T3 Code on your Mac

Open the PadelOS folder as the project, then paste:

```text
You are the release engineer for PadelOS, an iPhone + Apple Watch padel tournament
app (SwiftUI, shared SwiftPM package Packages/PadelKit, XcodeGen project.yml with the
generated PadelOS.xcodeproj committed). You are running on my Mac, in my clone of
github.com/Wrexist/PadelOS. Read CLAUDE.md, docs/RELEASE.md and PROJECT_STATUS.md
before doing anything.

HARD RULES
- Never print, cat, copy, commit or upload a .p8, .p12, .mobileprovision or password.
  If a step needs one, tell me which file or value and wait for me.
- Never revoke certificates, delete identifiers or profiles, or touch App Store
  Connect agreements, pricing or "Submit for Review". If Xcode or a script suggests
  revoking a certificate, stop and ask me.
- Never edit Apps/*/Localizable.xcstrings by hand (generated), never hand-edit
  PadelOS.xcodeproj (run scripts/xcodegen.sh), never weaken or skip a test or check
  to get green.
- Report what actually ran and what it printed. "Should work" is not a result.

PART A — prepare and archive without uploading
1. git fetch origin && git checkout main && git pull. If origin/main does not yet
   contain scripts/release/testflight-local.sh, use branch claude/ios-release-pipeline
   and tell me the PR is not merged yet.
2. Check the toolchain: xcodebuild -version (need Xcode 26+), node --version (need 18+;
   brew install node if missing). Confirm Xcode → Settings → Accounts has an Apple ID
   on team S3U8B8HH96; if not, ask me to sign in and wait.
3. Run the fast checks and show the output:
     swift test --package-path Packages/PadelKit
     node scripts/release/selftest.mjs
     node scripts/release/check-release.mjs
     scripts/xcodegen.sh && git status --short   (must show no change)
4. Run: scripts/release/testflight-local.sh --no-upload
   It archives with automatic signing, which registers app.padelos.PadelOS,
   .widgets, .watchkitapp, .watchkitapp.widgets and the App Group group.app.padelos
   on the team. If it fails, read build/release/archive.log or export.log, quote the
   real error lines, apply the fix the script printed or the matching row of
   docs/RELEASE.md §6, and retry once. If the fix needs me (Apple account, agreement,
   certificate limit) stop and tell me exactly what to do.
5. On success, verify the exported .ipa in build/release/export: unzip it to a temp
   folder and confirm (a) the Watch app and both .appex are inside, (b) every bundle
   has CFBundleShortVersionString/CFBundleVersion matching what the script printed,
   (c) PrivacyInfo.xcprivacy exists in PadelOS.app, PadelOSWatch.app and
   PadelOSWatchWidgets.appex, (d) `codesign -d --entitlements - --xml` on the watch app
   and watch widget shows group.app.padelos. Report each as pass/fail.

PART B — first upload (only after I say "upload" and the App Store Connect app
record for app.padelos.PadelOS exists)
6. Run scripts/release/testflight-local.sh (optionally with
   APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and
   APP_STORE_CONNECT_API_KEY_PATH that I export myself, which adds the preflight,
   the build-number lookup and the processing wait).
7. Report version, build number, and the processing result. If Apple marks the build
   INVALID, tell me to check the email Apple sent and help me fix the cause in code.

PART C — device testing support
8. When I report a bug from the device checklist (TESTING.md "Manual / device testing
   still required"), reproduce it from the code, write a failing PadelKit test where
   the logic allows, fix it, run the checks in step 3, and commit on a new branch
   claude/<short-name> with a clear message. Do not push to main directly.

Finish with a short report: what ran, results, version/build uploaded, files changed,
and anything still waiting on me.
```

---

## 3 · Claude in Chrome

Sign in to App Store Connect (appstoreconnect.apple.com) and the developer portal
(developer.apple.com/account) yourself first, including 2FA. Then open Claude in Chrome
and paste:

```text
You are helping me set up my iPhone + Apple Watch app "PadelOS" in App Store Connect,
the Apple Developer portal and GitHub. I am already signed in to all three. Work one
part at a time and report after each part.

FACTS
- Team ID S3U8B8HH96. Bundle ids: app.padelos.PadelOS (iPhone app),
  app.padelos.PadelOS.widgets, app.padelos.PadelOS.watchkitapp,
  app.padelos.PadelOS.watchkitapp.widgets. App Group: group.app.padelos.
- The app has no accounts, no backend, no analytics, no ads, no purchases. All data
  stays on the device.
- GitHub repository: github.com/Wrexist/PadelOS.

HARD RULES — never break these
- Never click Submit for Review, Add for Review, Release, Remove from Sale, Delete,
  Revoke, or anything about agreements, tax, banking, pricing tiers or payments.
- Never read out, copy, type or screenshot a private key, certificate, password or
  secret value. When a step needs one, stop and tell me to paste it myself.
- Before every Create, Save or Add, tell me exactly what you will submit and wait for
  me to say yes.
- If a page differs from what I describe, or asks for a password, 2FA code or
  payment, stop and ask me.

PART A — check identifiers (developer.apple.com → Certificates, Identifiers &
Profiles → Identifiers). Read only. For each of the four bundle ids report: exists
yes/no, and for the two watchkitapp ids whether App Groups is enabled with
group.app.padelos assigned. Also report whether Identifiers → App Groups lists
group.app.padelos. If anything is missing, tell me; my Mac agent registers them by
archiving once, so do not create them unless I ask.

PART B — app record (appstoreconnect.apple.com → Apps). If an app with bundle id
app.padelos.PadelOS exists, report its name and Apple ID and skip to PART C.
Otherwise prepare New App with: Platform iOS; Name "PadelOS" (if taken, propose
"PadelOS – Tournaments" and ask me); Primary language English (U.S.); Bundle ID
app.padelos.PadelOS; SKU padelos; User access Full Access. Show me the form and wait
for my yes before Create.

PART C — inside the app record
1. App Privacy: set data collection to "No, we do not collect data from this app"
   (Data Not Collected). Confirm with me before Save/Publish. The privacy policy URL
   field: if it is required here, stop and ask me for a URL; do not invent one.
2. App Information: Category Sports (primary). Report the age-rating questionnaire
   state; if it needs answering, propose all "None"/"No" answers (no violence, no
   gambling, no web access, no user-generated content shared publicly) and wait.
3. TestFlight → Internal Testing: create a group named "Internal" with automatic
   distribution of new builds ON, and add me as a tester. Confirm before Create.

PART D — API key for GitHub Actions (Users and Access → Integrations → App Store
Connect API → Team Keys). Report existing keys (name, role, key id; never anything
secret). If none has the Admin role and is meant for CI, prepare a new key named
"GitHub Actions PadelOS" with role Admin and wait for my yes. After it is created,
report the Key ID and the Issuer ID shown on the page, then STOP and tell me to click
"Download" myself (Apple allows it once) and keep the AuthKey_<id>.p8 file safe.

PART E — GitHub secrets (github.com/Wrexist/PadelOS → Settings → Secrets and
variables → Actions). Report which of these already exist (names only):
APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
APP_STORE_CONNECT_API_KEY_BASE64. For each missing one, open "New repository
secret", type only the NAME, and tell me to paste the value myself:
- KEY_ID and ISSUER_ID: the values you reported in PART D (I paste them).
- API_KEY_BASE64: I run `base64 -i AuthKey_<id>.p8 | pbcopy` on my Mac and paste.
Never type a secret value yourself.

PART F — after the first build has been uploaded (only when I ask): TestFlight →
Builds → iOS. Report the newest build's version, build number and status. If it asks
for export compliance, the answer is: the app uses no non-exempt encryption (this is
already declared in Info.plist, so it should not ask; tell me if it does). Report
whether the Internal group received it.

End with a table: every part, what you saw, what changed, what is waiting on me.
```

---

## 4 · Claude Code in the cloud (claude.ai/code, repo Wrexist/PadelOS)

```text
Repository Wrexist/PadelOS. Read CLAUDE.md and docs/RELEASE.md first.

PART 1 — land the release pipeline
1. Open a PR from claude/ios-release-pipeline into main titled "TestFlight pipeline
   from GitHub and from a Mac; release checks in CI" (summarise the branch's commits;
   no secrets). Subscribe to its activity.
2. CI runs on the PR. If anything fails, read the failing step's log, reproduce
   locally where possible (Linux: source scripts/setup-linux-toolchain.sh, then
   swift test, node scripts/release/selftest.mjs, node scripts/release/check-release.mjs,
   scripts/xcodegen.sh), fix the root cause and push. Remember macOS steps run under
   /bin/bash 3.2: no mapfile, brace variables before non-ASCII text, guard empty
   arrays under set -u. Never skip or weaken a check.
3. When CI is green, tell me it is ready to merge. Merge only if I say so.

PART 2 — first Mac-less TestFlight build (after I confirm the three
APP_STORE_CONNECT_* secrets exist and the app record exists)
4. Dispatch the "iOS TestFlight" workflow on main with upload=true and an empty
   version (uses MARKETING_VERSION from project.yml). Watch it without polling
   loops that burn time: check each job as it completes.
5. If preflight fails, quote its message; it names the missing secret, rejected key,
   missing app record or closed version. If archive/export fails, read the
   "Why signing failed" step and the export log, fix what is ours (workflow, scripts,
   project), and tell me exactly what is Apple-side (key role, agreement, certificate
   limit). Re-dispatch only after a real fix.
6. Report: run URL, version, build number, processing result (VALID/INVALID), and
   the artifact names (.ipa, dSYMs). Update PROJECT_STATUS.md's TestFlight row with
   the run id and date as evidence, on a branch with a PR.
```

---

## 5 · What "done" means

- A build with a version and build number you can name is **VALID** in TestFlight and
  installed on your iPhone, with the watch app installed on the paired Apple Watch.
- At least one of those builds came from the GitHub workflow (the Mac-less path works).
- `PROJECT_STATUS.md` records the run id / build number as evidence; the device
  checklist results are written down (pass/fail per item, device and OS).
- App Store submission is **not** part of this. It needs store screenshots, a privacy
  policy URL, a support URL and description, and your explicit decision.

## 6 · Shared facts

| Item | Value |
| --- | --- |
| Team ID | `S3U8B8HH96` (`DEVELOPMENT_TEAM` in `project.yml`) |
| Bundle ids | `app.padelos.PadelOS`, `…widgets`, `…watchkitapp`, `…watchkitapp.widgets` |
| App Group | `group.app.padelos` |
| Marketing version | `MARKETING_VERSION` in `project.yml` (1.0.0) |
| Build number | highest on App Store Connect + 1 (epoch seconds without an API key) |
| Secrets | `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_BASE64`; optional `APPLE_TEAM_ID`; optional manual signing `IOS_DISTRIBUTION_CERT_P12_BASE64`, `IOS_DISTRIBUTION_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILES_BASE64` |
| Mac command | `scripts/release/testflight-local.sh [--version X.Y.Z] [--no-upload] [--build N]` |
| GitHub | Actions → iOS TestFlight → Run workflow, or push tag `ios-vX.Y.Z` |
| Privacy | Data Not Collected; manifests in the iPhone app, watch app and complication |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in the iPhone Info.plist |
