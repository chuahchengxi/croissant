#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 chuahchengxi

# Read-only UI smoke test for a Developer build. Drives the real app through
# Accessibility (menu panel, quick panel, Settings), captures screenshots and
# fails loudly when a surface does not appear. It never changes preferences:
# everything it opens is closed again, and no toggle is flipped. Requires
# Accessibility + Screen Recording permission for the terminal running it.
#
# Usage: ./Tools/ui-smoke.sh [output-dir]
#   CROISSAINT_APP=path/to/App.app picks a build other than the installed
#   Developer one, e.g. "build/stage.noindex/Croissaint (Developer).app".
set -uo pipefail

APP="${CROISSAINT_APP:-/Applications/Croissaint (Developer).app}"
OUT="${1:-$(mktemp -d /tmp/croissaint-ui-smoke.XXXXXX)}"
mkdir -p "$OUT"
FAILURES=0

step() { echo "▸ $1"; }
fail() { echo "✗ $1" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ✓ $1"; }

if [[ ! -d "$APP" ]]; then
    echo "✗ $APP not found — run ./build.sh --dev --install, or set CROISSAINT_APP" >&2
    exit 1
fi
PROCESS=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")

ax() { osascript -e "tell application \"System Events\" to tell process \"$PROCESS\" to $1" 2>/dev/null; }
# Polls an Accessibility condition instead of sleeping a fixed time: a cold
# launch or a busy Mac can take seconds to put a surface on screen.
wait_for() {
    local condition=$1 tries=${2:-20}
    for (( i = 0; i < tries; i++ )); do
        [[ "$(ax "$condition")" == "true" ]] && return 0
        sleep 0.25
    done
    return 1
}
feature_on() { [[ "$(defaults read "$BUNDLE_ID" "featureAvailable.$1" 2>/dev/null)" == "1" ]]; }

PANEL='pop over 1 of menu bar item 1 of menu bar 2'

# A fresh install opens first-run setup, which every later step would trip
# over. Finishing it changes preferences, so that stays the user's job.
if [[ "$(defaults read "$BUNDLE_ID" hasOnboarded 2>/dev/null)" != "1" ]]; then
    echo "✗ $BUNDLE_ID has not finished first-run setup — open the app, complete it, then rerun" >&2
    exit 1
fi
if [[ "$BUNDLE_ID" != "com.croissaint.utils" ]] && pgrep -xq Croissaint; then
    echo "  ! the regular Croissaint is running; shared shortcuts (⌃⌘V) may go to it instead" >&2
fi

step "Launching the app"
open "$APP"
if ! wait_for 'exists menu bar item 1 of menu bar 2' 40; then
    fail "app did not put its status item in the menu bar"
    exit 1
fi
pass "process running with its status item"

step "Menu panel"
# The status item toggles the panel, so only click when it is closed, and
# allow one retry for a click that lands while the app is still settling.
open_panel() {
    for attempt in 1 2; do
        [[ "$(ax "exists $PANEL")" == "true" ]] && return 0
        ax 'click menu bar item 1 of menu bar 2' >/dev/null
        wait_for "exists $PANEL" 16 && return 0
    done
    return 1
}
if open_panel; then
    pass "panel popover opened"
    screencapture -x "$OUT/panel.png"
else
    fail "panel popover did not open"
fi
osascript -e 'tell application "System Events" to key code 53' >/dev/null
wait_for "not (exists $PANEL)" 8

step "Quick panel"
if feature_on quickLauncher; then
    osascript -e 'tell application "System Events" to keystroke "v" using {control down, command down}' >/dev/null
    if wait_for 'exists window "Croissaint"' 16; then
        pass "quick panel window at $(ax 'get position of window "Croissaint"')"
        screencapture -x "$OUT/quick-panel.png"
    else
        fail "quick panel window did not appear"
    fi
    osascript -e 'tell application "System Events" to key code 53' >/dev/null
    wait_for 'not (exists window "Croissaint")' 8
else
    echo "  – skipped: the quick panel feature is not installed"
fi

step "Settings window"
# Found by identifier, not position: the tab row grows with every feature.
SETTINGS_BUTTON="(first button of group 1 of $PANEL whose value of attribute \"AXIdentifier\" is \"panel.settings\")"
if open_panel && ax "click $SETTINGS_BUTTON" >/dev/null && wait_for 'exists window "Croissaint Settings"' 16; then
    pass "settings window at $(ax 'get position of window "Croissaint Settings"')"
    screencapture -x "$OUT/settings.png"
    ax 'click (first button of window "Croissaint Settings" whose subrole is "AXCloseButton")' >/dev/null
else
    fail "settings window did not open"
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "UI SMOKE OK — screenshots in $OUT"
else
    echo "UI SMOKE FAILED ($FAILURES failure(s)) — screenshots in $OUT" >&2
    exit 1
fi
