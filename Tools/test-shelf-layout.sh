#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Manual check, not part of ./build.sh --test: on CI's macOS 15 runner the
# expanded docked shelf measures at pill size (82x47) with both the 0.2.5 and
# the explicit-sizing code, and it is not yet known whether that is the VM or
# a real macOS 14-15 bug. Confirm on a real macOS 15 Mac before relying on it.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/croissaint-shelf-layout.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
TEST_ID="com.croissaint.tests.shelf-layout.$(uuidgen)"
TEST_APP="$TEST_DIR/ShelfLayoutTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_DIR/tmp"
cat > "$TEST_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$TEST_ID</string>
<key>CFBundleExecutable</key><string>ShelfLayoutTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" || ! -d "$PINNED_SDK" ]]; then
    SDK=$(xcrun --show-sdk-path)
else
    SDK="$PINNED_SDK"
fi
SDK_FLAGS=()
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    SDK_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi
SOURCES=(Sources/Croissaint/**/*.swift)
SOURCES=(${SOURCES:#Sources/Croissaint/App/CroissaintApp.swift})
swiftc -Onone -j 4 -module-cache-path /tmp/croissaint-module-cache -target arm64-apple-macosx14.0 -sdk "$SDK" "${SDK_FLAGS[@]}" \
    -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem "${SOURCES[@]}" Tests/UI/ShelfLayoutTests.swift \
    -o "$TEST_APP/Contents/MacOS/ShelfLayoutTests"
TMPDIR="$TEST_DIR/tmp/" "$TEST_APP/Contents/MacOS/ShelfLayoutTests"
