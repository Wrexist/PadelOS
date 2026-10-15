#!/usr/bin/env bash
# scripts/release/testflight-local.sh — archive PadelOS on your Mac and send it to TestFlight.
#
#   scripts/release/testflight-local.sh                  # version from project.yml, upload
#   scripts/release/testflight-local.sh --version 1.0.1  # ship a specific marketing version
#   scripts/release/testflight-local.sh --no-upload      # archive + export an .ipa only
#   scripts/release/testflight-local.sh --build 42       # force a build number
#
# Signing uses the Apple ID signed in to Xcode (Xcode → Settings → Accounts) with
# automatic signing, exactly like Product → Archive → Distribute App, so the
# first run also registers the four bundle ids and the App Group for the team.
# Set APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and either
# APP_STORE_CONNECT_API_KEY_PATH (path to AuthKey_XXXX.p8) or
# APP_STORE_CONNECT_API_KEY_BASE64 to sign and upload with the API key instead
# (also enables the build-number lookup and the preflight).
#
# Output: build/release/PadelOS-<version>-<build>.xcarchive (+ export/ with the
# .ipa when --no-upload). Logs: build/release/*.log
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERSION=""
BUILD=""
UPLOAD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --no-upload) UPLOAD=0; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown option $1 (see --help)"; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
die() { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "This script needs a Mac with Xcode. From Linux, use the 'iOS TestFlight' GitHub workflow."
command -v xcodebuild >/dev/null || die "xcodebuild not found. Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app"
command -v node >/dev/null || die "Node is needed for the release checks: brew install node"

TEAM_ID=$(node scripts/release/lib/project.mjs team)
VERSION="${VERSION:-$(node scripts/release/lib/project.mjs version)}"

step "Release checks"
node scripts/release/check-release.mjs --version "$VERSION"

step "Xcode"
xcodebuild -version
SDK=$(xcrun --sdk iphoneos --show-sdk-version)
if [ "${SDK%%.*}" -lt 26 ]; then
  [ "$UPLOAD" = 1 ] && die "iOS SDK $SDK: App Store Connect only accepts builds made with the iOS 26 SDK or later. Update Xcode."
  echo "⚠︎ iOS SDK $SDK is too old for an upload; continuing because --no-upload was given."
fi

# Archive what project.yml says, with the same pinned XcodeGen CI uses.
step "Regenerate PadelOS.xcodeproj from project.yml"
scripts/xcodegen.sh
git diff --quiet -- PadelOS.xcodeproj || echo "⚠︎ PadelOS.xcodeproj changed; commit it together with your project.yml change."

AUTH=()
KEY_FILE=""
if [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] && [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
  if [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ]; then
    KEY_FILE="$APP_STORE_CONNECT_API_KEY_PATH"
  elif [ -n "${APP_STORE_CONNECT_API_KEY_BASE64:-}" ]; then
    KEY_FILE="$(mktemp -d)/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
    if printf '%s' "$APP_STORE_CONNECT_API_KEY_BASE64" | grep -q 'BEGIN PRIVATE KEY'; then
      printf '%s' "$APP_STORE_CONNECT_API_KEY_BASE64" | tr -d '\r' > "$KEY_FILE"
    else
      printf '%s' "$APP_STORE_CONNECT_API_KEY_BASE64" | tr -d '[:space:]' | base64 --decode > "$KEY_FILE"
    fi
    trap 'rm -f "$KEY_FILE"' EXIT
  fi
fi
if [ -n "$KEY_FILE" ]; then
  [ -f "$KEY_FILE" ] || die "API key file not found: $KEY_FILE"
  AUTH=(-authenticationKeyPath "$KEY_FILE" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID")
  step "App Store Connect preflight (API key)"
  PREFLIGHT=(--version "$VERSION")
  [ "$UPLOAD" = 1 ] && PREFLIGHT+=(--upload)
  APP_STORE_CONNECT_API_KEY_PATH="$KEY_FILE" node scripts/release/preflight.mjs "${PREFLIGHT[@]}"
  echo "Signing and uploading with API key $APP_STORE_CONNECT_KEY_ID."
else
  echo "Signing and uploading with the Apple ID signed in to Xcode (team $TEAM_ID)."
fi

if [ -z "$BUILD" ]; then
  BUILD=$(APP_STORE_CONNECT_API_KEY_PATH="$KEY_FILE" node scripts/release/next-build-number.mjs)
fi
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "Build number must be an integer (got '$BUILD')."

OUT="$ROOT/build/release"
ARCHIVE="$OUT/PadelOS-$VERSION-$BUILD.xcarchive"
mkdir -p "$OUT"

explain_failure() { # $1 = log file
  local log="$1"
  if grep -qiE 'requires a development team|No Account for Team|No accounts' "$log"; then
    echo "→ Xcode is not signed in to team $TEAM_ID. Xcode → Settings → Accounts → + → Apple ID, then re-run."
    echo "  (Or export APP_STORE_CONNECT_KEY_ID / _ISSUER_ID / _API_KEY_PATH to sign with an API key.)"
  elif grep -qiE 'maximum number of certificates|choose a certificate to revoke' "$log"; then
    echo "→ The team has the maximum number of certificates. Revoke an unused one at"
    echo "  developer.apple.com/account/resources/certificates, or reuse an existing one from Xcode → Settings → Accounts → Manage Certificates."
  elif grep -qiE 'program membership|not eligible for this feature|PLA|License Agreement' "$log"; then
    echo "→ Apple refused provisioning: check developer.apple.com/account for an expired membership or an unaccepted agreement."
  elif grep -qiE 'No profiles for|doesn.t support the .*App Group|provisioning profile' "$log"; then
    echo "→ Provisioning failed. Open PadelOS.xcodeproj once, select each target → Signing & Capabilities with team $TEAM_ID"
    echo "  and let Xcode fix the App Group group.app.padelos, then re-run."
  elif grep -qiE 'No suitable application records|Error Downloading App Information|app record' "$log"; then
    echo "→ App Store Connect has no app for app.padelos.PadelOS yet: App Store Connect → Apps → + → New App (docs/RELEASE.md §2)."
  elif grep -qiE 'bundle version must be higher|has already been used|redundant binary' "$log"; then
    echo "→ That build number is taken. Re-run (the next number is looked up with an API key) or pass --build N."
  elif grep -qiE 'already been approved|train.*closed|version .* is not valid' "$log"; then
    echo "→ Version $VERSION is closed for new builds. Re-run with --version <higher>."
  fi
}

step "Archive $VERSION ($BUILD)"
if ! xcodebuild archive \
    -project PadelOS.xcodeproj -scheme PadelOS -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    > "$OUT/archive.log" 2>&1; then
  grep -E 'error:|warning: .*(sign|profile)' "$OUT/archive.log" | tail -20 || true
  explain_failure "$OUT/archive.log"
  die "Archive failed. Full log: $OUT/archive.log"
fi
echo "Archive: $ARCHIVE"

DESTINATION=$([ "$UPLOAD" = 1 ] && echo upload || echo export)
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

step "$([ "$UPLOAD" = 1 ] && echo 'Export and upload to App Store Connect' || echo 'Export the .ipa')"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
    > "$OUT/export.log" 2>&1; then
  grep -E 'error|Error' "$OUT/export.log" | tail -20 || true
  explain_failure "$OUT/export.log"
  die "Export failed. Full log: $OUT/export.log"
fi

if [ "$UPLOAD" = 1 ]; then
  printf '\n\033[32m✓ PadelOS %s (%s) uploaded.\033[0m Apple processes it for 5–30 minutes;\n' "$VERSION" "$BUILD"
  echo "  internal testers get it in TestFlight when processing finishes."
  if [ -n "$KEY_FILE" ]; then
    step "Waiting for App Store Connect processing (Ctrl-C is safe)"
    APP_STORE_CONNECT_API_KEY_PATH="$KEY_FILE" node scripts/release/wait-for-processing.mjs --version "$VERSION" --build "$BUILD" --timeout 45 || true
  fi
else
  printf '\n\033[32m✓ Exported:\033[0m %s\n' "$(ls "$OUT"/export/*.ipa)"
  echo "  Upload later with Transporter, or re-run without --no-upload."
fi
