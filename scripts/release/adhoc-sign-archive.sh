#!/usr/bin/env bash
# scripts/release/adhoc-sign-archive.sh <path/to/PadelOS.xcarchive> <TEAM_ID>
#
# CI archives PadelOS UNSIGNED, then lets `xcodebuild -exportArchive` apply the
# App Store signature (cloud-managed certificate, or the imported .p12). The
# reason is Apple's certificate cap: signing the archive on a fresh runner makes
# Xcode mint a new development certificate every time, and Airline-Empire's
# release run 38104614398 failed when the team (shared with Wrexist's other
# apps) reached the maximum.
#
# An unsigned archive carries no entitlements, and export re-signs with the
# entitlements it finds in each binary. Without this step the watch app and
# its complication would silently lose the App Group (group.app.padelos) and
# the complication would never see the active match. So: give every bundle an
# ad-hoc signature ("-", no certificate) carrying its entitlements, innermost
# first. Export replaces each signature with the real one.
#
# Entitlements come from Apps/*/<ProductName>.entitlements when that file
# exists, plus application-identifier and team-identifier.
set -euo pipefail

ARCHIVE="${1:?usage: adhoc-sign-archive.sh <archive> <team-id>}"
TEAM_ID="${2:?usage: adhoc-sign-archive.sh <archive> <team-id>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "::error::No .app in $ARCHIVE/Products/Applications"; exit 1; }

# Every nested bundle plus the app, deepest path first (inside out).
BUNDLES=()
while IFS= read -r line; do BUNDLES+=("${line#* }"); done < <(
  { find "$APP" -mindepth 1 \( -name '*.app' -o -name '*.appex' -o -name '*.framework' -o -name '*.dylib' \) -print; echo "$APP"; } |
    awk -F/ '{ print NF " " $0 }' | sort -rn -k1,1
)

for BUNDLE in "${BUNDLES[@]}"; do
  case "$BUNDLE" in
    *.framework|*.dylib)
      codesign --force --sign - --timestamp=none "$BUNDLE"
      echo "ad-hoc signed ${BUNDLE#"$APP"/}"
      continue
      ;;
  esac
  NAME=$(basename "$BUNDLE"); NAME="${NAME%.*}"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE/Info.plist")
  ENT="$WORK/$NAME.entitlements"
  SOURCE=$(find "$ROOT/Apps" -maxdepth 2 -name "$NAME.entitlements" | head -1)
  if [ -n "$SOURCE" ]; then
    cp "$SOURCE" "$ENT"
  else
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$ENT"
  fi
  /usr/libexec/PlistBuddy -c "Add :application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENT"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"
  # App Store builds talk to CloudKit's production environment (shared tournaments).
  if grep -q 'icloud-services' "$ENT"; then
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.icloud-container-environment string Production" "$ENT"
  fi
  codesign --force --sign - --timestamp=none --entitlements "$ENT" "$BUNDLE"

  if [ -n "$SOURCE" ] && grep -q 'application-groups' "$SOURCE"; then
    codesign -d --entitlements - "$BUNDLE" 2>/dev/null | grep -q 'group\.' ||
      { echo "::error::$NAME lost its App Group entitlement while signing."; exit 1; }
  fi
  echo "ad-hoc signed ${BUNDLE#"$(dirname "$APP")"/} ($BUNDLE_ID${SOURCE:+, entitlements from ${SOURCE#"$ROOT"/}})"
done
