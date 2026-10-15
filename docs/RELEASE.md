# Releasing PadelOS to TestFlight

Two ways to ship the same build, using the same checks. For copy-paste prompts that
drive the whole setup with T3 Code, Claude in Chrome and Claude Code, see
[MASTER_PROMPT.md](MASTER_PROMPT.md).

| | From GitHub (no Mac needed) | From your Mac |
| --- | --- | --- |
| Command | Actions → **iOS TestFlight** → Run workflow, or `git tag ios-v1.0.1 && git push origin ios-v1.0.1` | `scripts/release/testflight-local.sh` |
| Signs with | App Store Connect API key (Apple's cloud-managed certificate), or the certificate + profiles in secrets | The Apple ID signed in to Xcode, or an API key from the environment |
| Build number | Highest build on App Store Connect + 1 | Same (with an API key), else epoch seconds |
| Waits for processing | Yes, on a cheap Linux job | Yes, when an API key is set |

Both run `scripts/release/check-release.mjs` first, which fails in milliseconds on
the things App Store Connect otherwise rejects after the upload: a missing or
transparent icon, a missing privacy manifest (ITMS-91053), unanswered export
compliance, mismatched bundle ids or App Group.

Bundle ids: `app.padelos.PadelOS` (iPhone), `.widgets` (Live Activity),
`.watchkitapp` (Apple Watch), `.watchkitapp.widgets` (complication). App Group:
`group.app.padelos`. Team: `S3U8B8HH96` (`DEVELOPMENT_TEAM` in `project.yml`).

---

## 1 · Once: your Mac (for the local path)

- Xcode 26 or later (App Store Connect only accepts the iOS 26 SDK), Node (`brew install node`).
- Xcode → Settings → Accounts → sign in with the Apple ID on team `S3U8B8HH96`.
- XcodeGen is downloaded automatically at the pinned version by `scripts/xcodegen.sh`.

## 2 · Once: App Store Connect app record and identifiers

1. **Identifiers and App Group.** The easiest way is one local run:
   `scripts/release/testflight-local.sh --no-upload`. Automatic signing registers the
   four bundle ids, enables App Groups and creates `group.app.padelos` for the team.
   (By hand: developer.apple.com → Identifiers → register the four ids, enable App
   Groups on the two watch ids and assign `group.app.padelos`.)
2. **App record.** App Store Connect → Apps → + → New App: platform iOS, name
   PadelOS (or what is free), bundle id `app.padelos.PadelOS`, SKU `padelos`.
   The watch app ships inside the iPhone app; it needs no record of its own.
3. **App Privacy.** "Data Not Collected": the app has no backend, no accounts and
   no analytics. The privacy manifests (`PrivacyInfo.xcprivacy` in the iPhone app,
   watch app and complication) say the same.
4. **TestFlight.** Create an internal testing group and add yourself; internal
   testers get every processed build automatically.

## 3 · Once: GitHub secrets (for the workflow)

Settings → Secrets and variables → Actions → New repository secret. These are the
same names (and can be the same values) as in Airline-Empire:

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → Users and Access → Integrations → Team Keys → key id |
| `APP_STORE_CONNECT_ISSUER_ID` | the issuer id shown above the key list |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` (or paste the .p8 text) |
| `APPLE_TEAM_ID` | optional; overrides `DEVELOPMENT_TEAM` from `project.yml` |

With only these, signing is **automatic**: the archive is built unsigned and the
export signs it with Apple's cloud-managed distribution certificate. That needs a
key with the **Admin** role, and nothing is created on the runner, so the team's
certificate limit (shared with Airline-Empire and Wooduko-3D) is never touched.

## 4 · Optional: manual signing

Use this if you do not want an Admin key in CI. Set all three or none:

| Secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_CERT_P12_BASE64` | Keychain Access → your *Apple Distribution* certificate with its private key → Export as .p12 → `base64 -i dist.p12` |
| `IOS_DISTRIBUTION_CERT_PASSWORD` | the .p12 password |
| `IOS_PROVISIONING_PROFILES_BASE64` | four **App Store Connect** profiles (developer.apple.com → Profiles), one per bundle id, zipped: `zip profiles.zip *.mobileprovision && base64 -i profiles.zip` |

The workflow reads each profile's bundle id and name from the file itself and fails
before archiving if one of the four is missing. Certificates and profiles expire
after a year; when they do, redo this section.

## 5 · Shipping a build

**GitHub:** Actions → iOS TestFlight → Run workflow. Leave *version* empty to use
`MARKETING_VERSION` from `project.yml`, or enter one (e.g. `1.0.1`). Untick *upload*
to archive, export and validate with Apple without uploading. A tag push
`ios-v1.0.1` always uploads version 1.0.1.

**Mac:**

```sh
scripts/release/testflight-local.sh                    # version from project.yml
scripts/release/testflight-local.sh --version 1.0.1
scripts/release/testflight-local.sh --no-upload        # .ipa in build/release/export
# Optional: API key instead of the Xcode account (also enables build-number lookup)
APP_STORE_CONNECT_KEY_ID=… APP_STORE_CONNECT_ISSUER_ID=… \
APP_STORE_CONNECT_API_KEY_PATH=~/keys/AuthKey_XXXX.p8 scripts/release/testflight-local.sh
```

A marketing version can take many builds until it is submitted for review; after
that, bump it (`MARKETING_VERSION` in `project.yml`, or `--version`). The preflight
refuses a version that is already in review or released.

## 6 · When it fails

Both paths translate Apple's signing errors into the fix. The common ones:

| Message | Fix |
| --- | --- |
| *requires a development team* / *No Account for Team* | Xcode → Settings → Accounts: sign in to team `S3U8B8HH96` |
| *maximum number of certificates* | Revoke an unused Apple Distribution certificate, or use manual signing (§4) |
| *program membership … not eligible* | Membership expired or an agreement is waiting at developer.apple.com/account; not a code problem |
| *No profiles for …* / *App Group* | Run the local script once (§2.1) so the ids and App Group are registered |
| *No suitable application records* | Create the app record (§2.2) |
| *bundle version must be higher* | Re-run; the next build number is looked up from App Store Connect |
| Build processed as INVALID | The reason is emailed to the account holder and shown in App Store Connect → TestFlight |

## 7 · Files

| File | Role |
| --- | --- |
| `.github/workflows/ios-testflight.yml` | preflight (Linux) → package tests (Linux) → archive, export, inspect, upload (macOS) → processing (Linux) |
| `scripts/release/testflight-local.sh` | the same release from a Mac |
| `scripts/release/check-release.mjs` | bundle rules App Store Connect enforces (also runs in CI on every change) |
| `scripts/release/preflight.mjs` | API key, app record, version state, registered identifiers |
| `scripts/release/next-build-number.mjs` | next CFBundleVersion from App Store Connect |
| `scripts/release/wait-for-processing.mjs` | polls until the build is VALID |
| `scripts/release/adhoc-sign-archive.sh` | restores each bundle's entitlements on the unsigned CI archive |
| `scripts/release/selftest.mjs` | offline tests of the tooling (JWT, key decoding, project.yml parsing) |
| `scripts/xcodegen.sh` | the pinned XcodeGen that generates the committed `PadelOS.xcodeproj` |
