#!/usr/bin/env bash
# scripts/xcodegen.sh [xcodegen args…] — run the pinned XcodeGen (default: generate).
#
# PadelOS.xcodeproj is committed so the project opens straight in Xcode, and CI
# fails when it differs from what project.yml generates. That only works if
# everyone generates with the same XcodeGen: Homebrew's 2.46.0 rewrites two
# lines of a 2.44.1 project. So the version is pinned here and the official
# macOS release binary is downloaded into build/tools on first use.
#
# On Linux (cloud sessions) there is no release binary: build it from source,
#   git clone --depth 1 --branch 2.44.1 https://github.com/yonaskolb/XcodeGen && swift build -c release
# and put .build/release/xcodegen on PATH (needs USER set). This script uses
# any xcodegen on PATH that reports the pinned version.
set -euo pipefail

VERSION=2.44.1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/build/tools/xcodegen-$VERSION"

BIN=""
if command -v xcodegen >/dev/null && [ "$(xcodegen --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')" = "$VERSION" ]; then
  BIN="$(command -v xcodegen)"
elif [ -x "$TOOLS/xcodegen/bin/xcodegen" ]; then
  BIN="$TOOLS/xcodegen/bin/xcodegen"
elif [ "$(uname)" = "Darwin" ]; then
  echo "Downloading XcodeGen ${VERSION}…" >&2
  mkdir -p "$TOOLS"
  curl -fsSL --retry 3 -o "$TOOLS/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
  unzip -q -o "$TOOLS/xcodegen.zip" -d "$TOOLS"
  BIN="$TOOLS/xcodegen/bin/xcodegen"
else
  echo "XcodeGen $VERSION not found; see the header of $0 for building it on Linux." >&2
  exit 1
fi

cd "$ROOT"
export USER="${USER:-$(id -un)}"
if [ $# -eq 0 ]; then set -- generate --quiet; fi
exec "$BIN" "$@"
