#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Croissaint

# Builds Croissaint, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# Flags: --dev builds the local-only "Croissaint (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications;
# --allow-adhoc permits signing without an identity (see the signing block below).
DEV=0
INSTALL=0
TEST=0
ALLOW_ADHOC=0
for arg in "$@"; do
    case "$arg" in
        --dev)         DEV=1 ;;
        --install)     INSTALL=1 ;;
        --test)        TEST=1 ;;
        --allow-adhoc) ALLOW_ADHOC=1 ;;
    esac
done

if (( DEV )); then
    APP_NAME="Croissaint (Developer)"
    EXECUTABLE="CroissaintDeveloper"
    APP_BUNDLE_ID="com.croissaint.utils.dev"
    BUILD_VARIANT_FLAGS=(-D CROISSAINT_DEVELOPMENT)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    BUILD_CONFIGURATION="debug"
else
    APP_NAME="Croissaint"
    EXECUTABLE="Croissaint"
    APP_BUNDLE_ID="com.croissaint.utils"
    BUILD_VARIANT_FLAGS=()
    APP_OPTIMIZATION_FLAGS=(-O)
    BUILD_CONFIGURATION="release"
fi
FAN_HELPER_ID="$APP_BUNDLE_ID.fan-control"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/Croissaint.entitlements"
LEGACY_IDENTITY="Croissaint Utils Signing"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

# Resolve the signing identity once, before anything is built, and reuse the
# answer everywhere below — asking twice can give two answers if the keychain
# locks mid-build, which is how a bundle ends up half signed.
#
# Refusing to fall back silently is the point. An ad-hoc signature's designated
# requirement is the binary's cdhash, so it changes on every rebuild and every
# TCC grant pinned to it goes stale: Accessibility keeps drawing a ticked box
# while AXIsProcessTrusted() returns false. A locked login keychain makes
# find-identity print nothing and is indistinguishable from owning no identity
# at all, so the common case for hitting this is not "fresh clone" — it is a
# working setup that quietly stopped signing.
DEVID="$(developer_id_identity)"
if [[ -n "$DEVID" ]]; then
    SIGN_MODE=devid
elif security find-identity -p codesigning 2>/dev/null | grep -q "$LEGACY_IDENTITY"; then
    SIGN_MODE=legacy
elif (( ALLOW_ADHOC )); then
    SIGN_MODE=adhoc
else
    echo "error: no code signing identity available; refusing to sign ad-hoc." >&2
    echo "  If you have never set one up:  Tools/setup-signing.sh" >&2
    echo "  If you have one, the keychain is probably locked:" >&2
    echo "      security unlock-keychain ~/Library/Keychains/login.keychain-db" >&2
    echo "  To build anyway:  $0 $@ --allow-adhoc" >&2
    echo "  Ad-hoc builds lose every granted permission on each rebuild." >&2
    exit 1
fi

codesign_with_timestamp_retry() {
    local attempt
    for attempt in 1 2 3; do
        if /usr/bin/codesign "$@"; then
            return 0
        fi
        if (( attempt < 3 )); then
            echo "  Developer ID signing failed; retrying ($((attempt + 1))/3)"
            sleep "$attempt"
        fi
    done
    return 1
}

write_swift_output_file_map() {
    local output_file="$1"
    local object_dir="$2"
    shift 2
    local source artifact

    {
        print -r -- "{"
        print -r -- "  \"\": {"
        print -r -- "    \"swift-dependencies\": \"$object_dir/master.swiftdeps\""
        print -r -- "  }"
        for source in "$@"; do
            artifact="${source//\//__}"
            artifact="${artifact%.swift}"
            print -r -- ","
            print -r -- "  \"$source\": {"
            print -r -- "    \"object\": \"$object_dir/$artifact.o\","
            print -r -- "    \"swift-dependencies\": \"$object_dir/$artifact.swiftdeps\""
            print -r -- "  }"
        done
        print -r -- "}"
    } > "$output_file"
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ "$SIGN_MODE" == devid ]]; then
        [[ -f "$helper" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$FAN_HELPER_ID" --sign "$DEVID" "$helper"
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$bundle"
    elif [[ "$SIGN_MODE" == legacy ]]; then
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign "$LEGACY_IDENTITY" "$helper"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign - "$helper"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    [[ -f "$helper" ]] && /usr/bin/codesign --verify --strict "$helper"
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${CROISSAINT_INSTALL_CHILD:-0}" != "1" ]]; then
    CROISSAINT_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    SDK="$(xcrun --show-sdk-path)"
elif [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
SDK_COMPAT_FLAGS=()
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    # Swift 6.4 can read the SDK 26 interfaces when given their compiler version.
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi
VM_STATISTICS_COMPAT_FLAGS=(-I Sources/VMStatisticsCompat)

# The defaults migrations under test need a real UserDefaults suite, and every
# suite leaves an empty plist in ~/Library/Preferences. The tests already clear
# the domains, but cfprefsd writes the emptied file back out around the time the
# process that owned it exits, so only a caller that outlives the run can remove
# them. `MetricsTests` keeps every suite name inside the single namespace swept
# here, which is what makes this sweep complete rather than a list to keep in
# step by hand. Adding a suite outside `com.croissaint.tests.` leaks a plist
# into the user's Preferences on every run — that is exactly how the previous
# namespaces drifted out of this sweep and left hundreds of stray files behind.
discard_test_preferences() {
    local preferences="$HOME/Library/Preferences"
    find "$preferences" -maxdepth 1 -name "com.croissaint.tests.*.plist" -delete 2>/dev/null || true
    # The harness has no bundle identifier, so `UserDefaults.standard` writes
    # a file named after the executable.
    rm -f "$preferences/metrics-tests.plist"
    local survivors
    survivors=$(find "$preferences" -maxdepth 1 \
        \( -name "com.croissaint.tests.*.plist" -o -name "metrics-tests.plist" \) \
        2>/dev/null | wc -l | tr -d ' ')
    if [[ "$survivors" != "0" ]]; then
        echo "✗ the test run left $survivors preference file(s) in $preferences" >&2
        return 1
    fi
}

# --test: compile and run the standalone unit tests (pure helpers only: metrics,
# Homebrew parsing, defaults, localization contracts; no app, no UI, no IOKit),
# then exit. Fast and deterministic; no XCTest needed.
if (( TEST )); then
    echo "▸ Building & running unit tests against $(basename "$SDK")…"
    rm -rf build
    mkdir -p build
    # The full app build below remains optimized and is the optimizer gate.
    # Unit assertions do not need optimization; avoiding it cuts most of the
    # test harness compile time without reducing the code the tests exercise.
    swiftc -Onone -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
        "${VM_STATISTICS_COMPAT_FLAGS[@]}" \
        Sources/Croissaint/Services/Media/MediaSupport.swift \
        Sources/Croissaint/Core/Defaults.swift \
        Sources/Croissaint/Core/FeatureCatalog.swift \
        Sources/Croissaint/Core/FeaturePresets.swift \
        Sources/Croissaint/Core/FeatureHubStrings.swift \
        Sources/Croissaint/Core/ShortcutSettingsStrings.swift \
        Sources/Croissaint/Core/SettingsBackupSupport.swift \
        Sources/Croissaint/Core/BackupStrings.swift \
        Sources/Croissaint/Core/BluetoothSleepStrings.swift \
        Sources/Croissaint/Core/SnippetStrings.swift \
        Sources/Croissaint/Core/BrightnessStrings.swift \
        Sources/Croissaint/Core/MediaImageStrings.swift \
        Sources/Croissaint/Core/QuickToggleStrings.swift \
        Sources/Croissaint/Core/ScreenshotStrings.swift \
        Sources/Croissaint/Core/RecentCaptureStrings.swift \
        Sources/Croissaint/Core/RecorderStrings.swift \
        Sources/Croissaint/Core/CameraPreviewStrings.swift \
        Sources/Croissaint/Core/ScratchpadStrings.swift \
        Sources/Croissaint/Core/FinderRenameStrings.swift \
        Sources/Croissaint/Core/CommandBarStrings.swift \
        Sources/Croissaint/Core/RadialMenuStrings.swift \
        Sources/Croissaint/Core/MenuBarAppearanceStrings.swift \
        Sources/Croissaint/Core/AppAppearance.swift \
        Sources/Croissaint/Core/AppearanceStrings.swift \
        Sources/Croissaint/Core/BatteryTimeStrings.swift \
        Sources/Croissaint/Core/KeepAwakeStrings.swift \
        Sources/Croissaint/Core/PermissionGuideStrings.swift \
        Sources/Croissaint/Core/FanControlStrings.swift \
        Sources/Croissaint/Services/FanControl/FanControlSupport.swift \
        Sources/Croissaint/Services/Snippets/TextSnippetSupport.swift \
        Sources/Croissaint/Services/RadialMenu/RadialMenuSupport.swift \
        Sources/Croissaint/Services/QuickTools/ScratchpadSupport.swift \
        Sources/Croissaint/Services/KillProcess/KillProcessSupport.swift \
        Sources/Croissaint/Services/Recorder/RecorderSupport.swift \
        Sources/Croissaint/Services/PrivateFileStore.swift \
        Sources/Croissaint/Services/Recorder/RecorderTakeStore.swift \
        Sources/Croissaint/Services/Recorder/RecorderMotion.swift \
        Sources/Croissaint/Services/Recorder/RecorderPointerTrack.swift \
        Sources/Croissaint/Services/Recorder/RecorderTypingTrack.swift \
        Sources/Croissaint/Services/Recorder/RecorderTimeline.swift \
        Sources/Croissaint/Services/Recorder/RecorderTextOverlay.swift \
        Sources/Croissaint/Services/Recorder/RecorderEditDocument.swift \
        Sources/Croissaint/Core/AppInfo.swift \
        Sources/Croissaint/Core/GlobalShortcut.swift \
        Sources/Croissaint/Core/Localization.swift \
        Sources/Croissaint/Core/Localizations/Strings+*.swift \
        Sources/Croissaint/Core/FeatureStrings.swift \
        Sources/Croissaint/Core/KillProcessStrings.swift \
        Sources/Croissaint/Core/WhatsAppDownloadStrings.swift \
        Sources/Croissaint/Core/WhatsAppOrganizerStrings.swift \
        Sources/Croissaint/Core/ReleaseNotes.swift \
        Sources/Croissaint/Core/URLCleaning.swift \
        Sources/Croissaint/Services/GeneralPasteboardAccess.swift \
        Sources/Croissaint/Services/Audio/MixerRoutingSupport.swift \
        Sources/Croissaint/Services/Audio/MusicLaunchSupport.swift \
        Sources/Croissaint/UI/MenuPanel/MixerPercentNativeTextField.swift \
        Sources/Croissaint/Services/Audio/BoostLimiter.swift \
        Sources/Croissaint/Services/Audio/MixerRender.swift \
        Sources/Croissaint/Services/DockPreview/DockPreviewSupport.swift \
        Sources/Croissaint/Services/Homebrew/HomebrewSupport.swift \
        Sources/Croissaint/Services/AppUpdates/AppUpdatesSupport.swift \
        Sources/Croissaint/Core/AppUpdateStrings.swift \
        Sources/Croissaint/Core/DiskImageInstallerStrings.swift \
        Sources/Croissaint/Services/DiskImageInstaller/DiskImageInstallerSupport.swift \
        Sources/Croissaint/Services/Clipboard/ClipboardHistorySupport.swift \
        Sources/Croissaint/Services/Clipboard/ClipboardAutoClearSupport.swift \
        Sources/Croissaint/Services/AutoQuit/AutoQuitSupport.swift \
        Sources/Croissaint/Services/Shelf/ShelfSupport.swift \
        Sources/Croissaint/Services/Finder/FinderRenameSupport.swift \
        Sources/Croissaint/Services/Update/UpdateInstallerSupport.swift \
        Sources/Croissaint/Services/Update/UpdateServiceSupport.swift \
        Sources/Croissaint/Services/InstalledApps.swift \
        Sources/Croissaint/Services/LaunchAtLoginSupport.swift \
        Sources/Croissaint/UI/Settings/SettingsSearchSupport.swift \
        Sources/Croissaint/UI/Settings/FeatureVisibilitySupport.swift \
        Sources/Croissaint/App/MenuBarSpacingSupport.swift \
        Sources/Croissaint/App/StatusItemAnchorSupport.swift \
        Sources/Croissaint/Services/DockClick/DockClickSupport.swift \
        Sources/Croissaint/Services/Finder/CutPasteProgressSupport.swift \
        Sources/Croissaint/Services/Finder/FinderPasteImageSupport.swift \
        Sources/Croissaint/Services/MiddleClick/MiddleClickSupport.swift \
        Sources/Croissaint/Services/MouseNavigation/MouseNavigationSupport.swift \
        Sources/Croissaint/Services/MouseButtons/MouseButtonShortcutSupport.swift \
        Sources/Croissaint/Services/MouseExceptions/MouseAppExceptionSupport.swift \
        Sources/Croissaint/Core/MouseButtonStrings.swift \
        Sources/Croissaint/Core/MouseExceptionStrings.swift \
        Sources/Croissaint/Core/ClipboardIgnoredAppsStrings.swift \
        Sources/Croissaint/Core/WindowPreviewExclusionStrings.swift \
        Sources/Croissaint/Core/SwitcherAppRulesStrings.swift \
        Sources/Croissaint/Services/QuickTools/QuickToolsSupport.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarSupport.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarPreferences.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarMath.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarUnits.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarEmoji.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarLinks.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarDates.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarRowShortcuts.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarSystemSettingsSupport.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarFileSearchSupport.swift \
        Sources/Croissaint/Services/CommandBar/CommandBarQueryMemory.swift \
        Sources/Croissaint/Services/SpotlightNamesSupport.swift \
        Sources/Croissaint/Services/QuickTools/MicMuteSupport.swift \
        Sources/Croissaint/Services/QuickTools/QuickTogglesSupport.swift \
        Sources/Croissaint/Services/QuickTools/ScreenshotCapturePolicy.swift \
        Sources/Croissaint/Services/QuickTools/ScreenshotSupport.swift \
        Sources/Croissaint/Services/QuickTools/WindowActivationPolicy.swift \
        Sources/Croissaint/Services/KeyboardDebounce/KeyboardDebounceSupport.swift \
        Sources/Croissaint/Services/SuperKey/SuperKeySupport.swift \
        Sources/Croissaint/Core/SuperKeyStrings.swift \
        Sources/Croissaint/Services/ScrollWheelSupport.swift \
        Sources/Croissaint/Services/SmoothScrollSupport.swift \
        Sources/Croissaint/Services/FocusFollowsMouse/FocusFollowsMouseSupport.swift \
        Sources/Croissaint/Services/Switcher/SwitcherModels.swift \
        Sources/Croissaint/Services/Switcher/SwitcherSupport.swift \
        Sources/Croissaint/Services/Switcher/SpaceHopSupport.swift \
        Sources/Croissaint/Services/Switcher/WindowUseOrder.swift \
        Sources/Croissaint/Services/Metrics/MetricFormat.swift \
        Sources/Croissaint/Services/KeepAwakeAutomationSupport.swift \
        Sources/Croissaint/Services/SudoersSupport.swift \
        Sources/Croissaint/Services/Metrics/BatteryTimeSupport.swift \
        Sources/Croissaint/Services/BoundedProcessRunner.swift \
        Sources/Croissaint/Services/ShellSupport.swift \
        Sources/Croissaint/Services/Metrics/NetworkProcessSupport.swift \
        Sources/Croissaint/Services/Metrics/NetworkSampler.swift \
        Sources/Croissaint/Services/Metrics/PeripheralBatterySupport.swift \
        Sources/Croissaint/Services/Metrics/DiskSupport.swift \
        Sources/Croissaint/Services/Metrics/MonitorSamplingPolicy.swift \
        Sources/Croissaint/Services/Metrics/MaxCapacityProbe.swift \
        Sources/Croissaint/Services/Metrics/TemperatureSensorSelector.swift \
        Sources/Croissaint/Services/Metrics/SustainedAlertGate.swift \
        Sources/Croissaint/Services/WindowLayout/WindowLayoutSupport.swift \
        Sources/Croissaint/Services/WindowLayout/WindowGestureSupport.swift \
        Sources/Croissaint/Core/WindowDirectionalStrings.swift \
        Sources/Croissaint/Services/CleaningMode/CleaningUnlockCounter.swift \
        Sources/Croissaint/Services/Display/ExtraBrightnessSupport.swift \
        Sources/Croissaint/Services/Display/BrightnessSupport.swift \
        Sources/Croissaint/Services/Cleaner/CleanerSupport.swift \
        Sources/Croissaint/Services/Audio/PreciseVolumeRollerSupport.swift \
        Sources/Croissaint/Services/Bluetooth/BluetoothSleepSupport.swift \
        Sources/Croissaint/Services/Cleaner/CleanerPolicy.swift \
        Sources/Croissaint/Services/Cleaner/CleanerSchedule.swift \
        Sources/Croissaint/Services/Uninstall/UninstallerSupport.swift \
        Sources/Croissaint/Services/ManagedDownloads/WhatsAppDownloadSupport.swift \
        Sources/Croissaint/Services/Metrics/VMStatisticsDecoder.swift \
        Sources/Croissaint/Services/DesktopPet/SpeciesCatalog.swift \
        Sources/Croissaint/Services/DesktopPet/SpeciesCatalogData.swift \
        Sources/Croissaint/Services/DesktopPet/PetAnimationPackSupport.swift \
        Sources/Croissaint/Services/DesktopPet/PetSpriteMetrics.swift \
        Sources/Croissaint/Services/DesktopPet/PetMoveCatalog.swift \
        Sources/Croissaint/Services/DesktopPet/PetMoveArt.swift \
        Sources/Croissaint/Services/DesktopPet/PetItemKind.swift \
        Sources/Croissaint/Services/DesktopPet/PetNapSchedule.swift \
        Sources/Croissaint/Services/DesktopPet/PetCatchDifficulty.swift \
        Tests/MetricsTests.swift \
        -o build/metrics-tests
    # `set -e` would end the script on a failing run before the sweep below.
    test_status=0
    ./build/metrics-tests || test_status=$?
    discard_test_preferences || test_status=1
    exit $test_status
fi

echo "▸ Compiling ($BUILD_CONFIGURATION) against $(basename "$SDK")…"
APP_SOURCES=(Sources/Croissaint/**/*.swift)
if (( DEV )); then
    APP_OBJECT_DIR="build/objects/$EXECUTABLE"
    mkdir -p build "$APP_OBJECT_DIR"
    APP_OUTPUT_FILE_MAP="$APP_OBJECT_DIR/output-file-map.json"
    write_swift_output_file_map "$APP_OUTPUT_FILE_MAP" "$APP_OBJECT_DIR" "${APP_SOURCES[@]}"
    swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -incremental -j "$(sysctl -n hw.logicalcpu)" \
        -output-file-map "$APP_OUTPUT_FILE_MAP" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${VM_STATISTICS_COMPAT_FLAGS[@]}" \
        "${BUILD_VARIANT_FLAGS[@]}" \
        "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"
else
    rm -rf build
    mkdir -p build
    swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -target "$TARGET" -sdk "$SDK" \
        "${SDK_COMPAT_FLAGS[@]}" "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
        "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"
fi

echo "▸ Compiling protected fan helper…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
    Sources/Croissaint/Services/FanControl/FanControlSupport.swift \
    Sources/Croissaint/Services/FanControl/FanControlXPC.swift \
    Sources/Croissaint/Services/SystemMonitor/SMCClient.swift \
    Sources/Croissaint/Services/Metrics/TemperatureSensorSelector.swift \
    Sources/Croissaint/Services/FanControl/FanControlHardware.swift \
    Sources/FanControlHelper/main.swift \
    -o "build/$FAN_HELPER_ID"
"build/$FAN_HELPER_ID" --selftest

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true
ACTOOL_BIN="$(xcrun --find actool 2>/dev/null || true)"
ICON_TMP="$(mktemp -d)"
ADAPTIVE_SKIP=""
if [[ -z "$ACTOOL_BIN" ]]; then
    ADAPTIVE_SKIP="actool not found (adaptive icons need Xcode 26+)"
else
    echo "▸ Compiling adaptive icon catalog…"
    # actool crashes on File Provider-synced paths, so compile a local copy.
    ditto "Resources/Brand/AppIcon.icon" "$ICON_TMP/AppIcon.icon"
    # Xcode 27 beta actool requires the --compile target directory to already exist.
    mkdir -p "$ICON_TMP/catalog"
    if "$ACTOOL_BIN" "$ICON_TMP/AppIcon.icon" \
            --compile "$ICON_TMP/catalog" \
            --app-icon AppIcon \
            --platform macosx \
            --target-device mac \
            --minimum-deployment-target 14.0 \
            --enable-on-demand-resources NO \
            --output-partial-info-plist "$ICON_TMP/partial-info.plist" \
            >"$ICON_TMP/actool.log" 2>&1 && [[ -s "$ICON_TMP/catalog/Assets.car" ]]; then
        mv "$ICON_TMP/catalog/Assets.car" build/Assets.car
    else
        ADAPTIVE_SKIP="actool could not compile the catalog"
    fi
fi
if [[ -n "$ADAPTIVE_SKIP" ]]; then
    cp "$ICON_TMP/actool.log" build/actool-failure.log 2>/dev/null || true
    echo "  adaptive icon skipped: $ADAPTIVE_SKIP (Dock falls back to AppIcon.icns)"
fi
rm -rf "$ICON_TMP"

echo "▸ Assembling and signing bundle…"
STAGE="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" \
    "$STAGE/Contents/Library/LaunchDaemons" "$STAGE/Contents/Library/LaunchServices"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp "build/$FAN_HELPER_ID" "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID"
cp Resources/com.croissaint.utils.fan-control.plist \
    "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.croissaint.utils.dev" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Croissaint (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Croissaint (Developer)" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    FAN_PLIST="$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
    /usr/libexec/PlistBuddy -c "Set :Label $FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Delete :MachServices:com.croissaint.utils.fan-control" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Add :MachServices:$FAN_HELPER_ID bool true" "$FAN_PLIST"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :CroissaintBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
FAN_HELPER_VERSION="$(
    export LC_ALL=C
    /usr/bin/shasum -a 256 \
        "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
        "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist" \
        | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
)"
/usr/libexec/PlistBuddy -c "Add :CroissaintFanControlHelperVersion string '$FAN_HELPER_VERSION'" \
    "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
# The desktop pet's animation table. 21 KB, read once at first buddy frame —
# bundled rather than downloaded so it can never disagree with the parser
# that reads it (PetAnimationPack.swift).
cp Resources/pet-animation-pack.bin "$STAGE/Contents/Resources/pet-animation-pack.bin"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -f build/Assets.car ]]; then
    cp build/Assets.car "$STAGE/Contents/Resources/Assets.car"
fi
if [[ -d Resources/Gifs ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/*.gif "$STAGE/Contents/Resources/Gifs/"
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "Croissaint Utils Signing" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — only with --allow-adhoc, because the resulting designated
#      requirement is a bare cdhash that every rebuild invalidates.
codesign_app() {
    local target="$1"
    if [[ "$SIGN_MODE" == devid ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif [[ "$SIGN_MODE" == legacy ]]; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

codesign_fan_helper() {
    local target="$1"
    if [[ "$SIGN_MODE" == devid ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$FAN_HELPER_ID" --sign "$DEVID" "$target"
    elif [[ "$SIGN_MODE" == legacy ]]; then
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"

    if [[ "$SIGN_MODE" == devid ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif [[ "$SIGN_MODE" == legacy ]]; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (--allow-adhoc) — permissions reset on every rebuild"
    fi
    [[ -f "$helper" ]] && codesign_fan_helper "$helper"
    codesign_app "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        [[ -f "$helper" ]] && codesign_fan_helper "$helper"
        codesign_app "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    [[ -f "$helper" ]] && codesign --verify --strict "$helper"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

mkdir -p "build/stage"
BUILD_STAGE="build/stage/$APP_NAME.app"
rm -rf "$BUILD_STAGE"
ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
    if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
        echo "  build/stage copy has local filesystem metadata; temp bundle was verified"
    else
        codesign --verify --deep --strict "$BUILD_STAGE"
    fi
fi
echo "✓ Bundle ready: $BUILD_STAGE"

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Remove the pre-rename apps so two menu bar items never coexist. Same bundle
    # id, so macOS keeps the granted permissions for the new bundle.
    # "Vorss" is the filename of a bundle that may still sit in /Applications,
    # not a reference to the upstream project: renaming it here would strand
    # that app rather than remove it, so this string has to keep the old name.
    for legacy in "Vorss:Vorss" "Croissaint Utils:CroissaintUtils"; do
        name="${legacy%%:*}"; proc="${legacy##*:}"
        if [[ -d "/Applications/$name.app" ]]; then
            stop_process "$proc"
            rm -rf "/Applications/$name.app"
            echo "  (legacy $name.app removed)"
        fi
    done
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
