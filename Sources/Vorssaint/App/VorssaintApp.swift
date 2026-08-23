// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The process entry point, dispatching between two lifecycles:
///
/// - **Bundled** (a real .app from build.sh): SwiftUI owns startup and the
///   run loop through `VorssaintApp`.
/// - **Bare binary** (`swift run`, an Xcode Swift-package scheme, ad-hoc
///   probing runs): there is no bundle, and SwiftUI's lifecycle cannot start
///   without one — it throws `NSInternalInconsistencyException
///   ("bundleProxyForCurrentProcess is nil")` while setting up, because the
///   scene machinery reads a bundle identity that a naked executable simply
///   does not have. Those runs get the pre-migration bootstrap instead: the
///   AppKit run loop driven directly, with the same AppDelegate. Behavior is
///   identical to every release before the SwiftUI migration.
@main
enum VorssaintEntryPoint {
    static func main() {
        // Bundled means a real .app: the URL ends in ".app" AND carries a
        // bundle identity. Checking the identity alone is not enough — Xcode
        // writes a generated Info.plist beside package-built binaries, so a
        // run straight out of DerivedData reports an identifier while its
        // bundle URL is just the products directory, and SwiftUI still finds
        // no bundle proxy behind it.
        let url = Bundle.main.bundleURL
        if url.pathExtension == "app", Bundle.main.bundleIdentifier != nil {
            VorssaintApp.main()
        } else {
            runLegacyBareBinaryLifecycle()
        }
    }

    /// The former main.swift, kept verbatim for unbundled processes.
    fileprivate static func runLegacyBareBinaryLifecycle() -> Never {
        registerDefaultsAndRouteEarlyExits()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        exit(0)
    }

    /// Runs while the process is coming up, before the app finishes
    /// launching — the same point in startup the old top-level main.swift
    /// code executed at.
    fileprivate static func registerDefaultsAndRouteEarlyExits() {
        Defaults.register()
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.runAndExit()
        }
        if CommandLine.arguments.contains("--sensors") {
            SensorDump.runAndExit()
        }
        if CommandLine.arguments.contains("--uninstall") {
            Uninstaller.runAndExit()
        }
    }
}

/// The SwiftUI app lifecycle for bundled launches.
///
/// Everything the app does hangs off `AppDelegate` — the status items, the
/// anchored menu bar panel, the borderless overlay panels and the shelf tile
/// grid (which drags whole selections out, something `.onDrag` cannot do) are
/// AppKit by necessity and are untouched by this migration.
struct VorssaintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        VorssaintEntryPoint.registerDefaultsAndRouteEarlyExits()
    }

    var body: some Scene {
        // An accessory app owns no scene-presented windows: every surface it
        // shows (menu bar panel, Settings, onboarding, intros) is raised by
        // AppDelegate through AppKit windows hosting SwiftUI content. A body
        // must still declare a Scene, so this inert Settings scene stands in
        // for one: it never presents anything at launch, and the app's own
        // main menu (installed by AppDelegate) routes Cmd+, and every other
        // action to the real windows rather than to this placeholder.
        Settings {
            EmptyView()
        }
    }
}
