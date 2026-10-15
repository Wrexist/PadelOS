#!/usr/bin/env bash
# scripts/setup-linux-toolchain.sh — Swift 6.2.1 and the pinned XcodeGen on Linux
# (Ubuntu 24.04 x86_64, e.g. a Claude Code cloud session).
#
#   source scripts/setup-linux-toolchain.sh   # install if needed and put both on PATH
#
# Then: swift test --package-path Packages/PadelKit, and scripts/xcodegen.sh to
# regenerate PadelOS.xcodeproj exactly as CI does.
set -euo pipefail

SWIFT_VERSION=6.2.1
XCODEGEN_VERSION=2.44.1
TOOLS="${PADELOS_TOOLS:-$HOME/.padelos-tools}"
SWIFT_DIR="$TOOLS/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04"
XCODEGEN_DIR="$TOOLS/XcodeGen-$XCODEGEN_VERSION"
mkdir -p "$TOOLS"

if [ ! -x "$SWIFT_DIR/usr/bin/swift" ]; then
  echo "Installing Swift $SWIFT_VERSION into $TOOLS …"
  curl -fsSL --retry 3 \
    "https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404/swift-$SWIFT_VERSION-RELEASE/swift-$SWIFT_VERSION-RELEASE-ubuntu24.04.tar.gz" |
    tar --no-same-owner -xz -C "$TOOLS"
fi
export PATH="$SWIFT_DIR/usr/bin:$PATH"

if [ ! -x "$XCODEGEN_DIR/.build/release/xcodegen" ]; then
  echo "Building XcodeGen $XCODEGEN_VERSION (about two minutes) …"
  rm -rf "$XCODEGEN_DIR"
  git clone -q --depth 1 --branch "$XCODEGEN_VERSION" https://github.com/yonaskolb/XcodeGen.git "$XCODEGEN_DIR"
  (cd "$XCODEGEN_DIR" && swift build -c release >/dev/null)
fi
export PATH="$XCODEGEN_DIR/.build/release:$PATH"
export USER="${USER:-$(id -un)}"

swift --version | head -1
echo "XcodeGen $(xcodegen --version)"
