// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import Carbon.HIToolbox

/// A floating panel that can take the keyboard. `NSPanel` refuses key status
/// while borderless, which is what every text field and arrow-key list in the
/// app needs back.
class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension NSPanel {
    /// Whether the pointer is over the panel, with a two-point margin so a
    /// click landing exactly on the edge counts as inside.
    var containsPointer: Bool {
        frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }
}

extension NSPanel {
    /// The flags every floating overlay in the app sets the same way: a clear
    /// background it draws itself, no release on close, alive across an app
    /// switch, and present on every Space without joining the window cycle.
    /// Sixteen `ensurePanel()` bodies wrote the same eight lines out; only the
    /// size, the content and the knobs below genuinely differ.
    ///
    /// The `hidesOnDeactivate` parameter is spelled out rather than left to
    /// `NSPanel`, whose own default is the opposite of what an overlay wants.
    func configureAsOverlay(level: NSWindow.Level = .floating,
                            transient: Bool = false,
                            hasShadow: Bool = true,
                            movableByBackground: Bool = false,
                            hidesOnDeactivate: Bool = false) {
        self.level = level
        self.hasShadow = hasShadow
        self.hidesOnDeactivate = hidesOnDeactivate
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        isMovableByWindowBackground = movableByBackground
        collectionBehavior = transient
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
}

/// The monitors a floating panel needs to put itself away: the local/global
/// click pair that closes it when a click lands outside, and the observer that
/// closes it when another app comes forward. Every panel service wrote these
/// by hand and the teardown was identical in all of them; only the key handler
/// genuinely differs, so that stays with the service and is parked here with
/// `add` so one `removeAll` takes everything down.
final class PanelDismissMonitors {
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    /// Call `removeAll()` first: this adds to whatever is already installed so
    /// a service can park its own key handler alongside, in either order.
    ///
    /// - Parameters:
    ///   - isArmed: gates both dismissals. A panel hosting a file dialog or an
    ///     admin prompt has to survive the click that opens it.
    ///   - onOutsideClick: the panel's own hide/close.
    ///   - onOtherAppActivated: nil for a panel that should outlive an app
    ///     switch. Also gated by `isArmed`.
    func install(for panel: NSPanel,
                 isArmed: @escaping () -> Bool = { true },
                 onOutsideClick: @escaping () -> Void,
                 onOtherAppActivated: (() -> Void)? = nil) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        add(NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak panel] event in
            guard let panel, panel.isVisible, isArmed() else { return event }
            if event.window !== panel, !panel.containsPointer { onOutsideClick() }
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak panel] event in
            guard let panel, panel.isVisible, isArmed() else { return }
            if event.windowNumber != panel.windowNumber, !panel.containsPointer { onOutsideClick() }
        })

        guard let onOtherAppActivated else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard isArmed(),
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            onOtherAppActivated()
        }
    }

    /// Parks a monitor the service made itself (its key or flags handler) so it
    /// comes down with the rest. Takes the optional `NSEvent` monitor factories
    /// return directly.
    func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    func removeAll() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    deinit { removeAll() }
}

enum PanelKeys {
    /// ⌘1…⌘9 (and plain 1…9 where the panel has no text field) pick by
    /// position. Returns the zero-based index, or nil for any other key.
    static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }
}
