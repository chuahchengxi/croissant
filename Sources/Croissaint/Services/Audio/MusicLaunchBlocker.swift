// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit

/// Keeps the system music app from opening on its own, which macOS does
/// whenever a media key is pressed with no other player around to take it.
///
/// While the option is on, a launch of the music app that follows a media
/// key is terminated before its window appears, and an optional replacement
/// app opens instead. Opening the music app from the Dock, Spotlight or a
/// double-click is left alone. Nothing runs while the feature is off: no
/// observers, no taps, no cost.
final class MusicLaunchBlocker: ObservableObject {
    static let shared = MusicLaunchBlocker()

    /// The current and the legacy identifier of the system music app.
    static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]

    private var observers: [NSObjectProtocol] = []
    private let eventTap = EventTap()
    /// One media key press produces both a will-launch and a did-launch
    /// notification; the replacement should open once, not twice.
    private var lastReplacementLaunch: TimeInterval = 0
    private var lastMediaKeyAt: TimeInterval?

    private init() {}

    func syncWithPreferences() {
        if AppFeature.musicBlock.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.musicBlockEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty, !eventTap.isRunning else { return }
        installMediaKeyTap()
        let center = NSWorkspace.shared.notificationCenter
        // Will-launch usually wins the race before any window shows;
        // did-launch catches the rare launch that slips past it.
        observers = [NSWorkspace.willLaunchApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.handleLaunch(note)
            }
        }
    }

    func stop() {
        removeMediaKeyTap()
        lastMediaKeyAt = nil
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func handleLaunch(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              Self.blockedBundleIDs.contains(bundleID) else { return }
        if eventTap.isRunning {
            guard MusicLaunchSupport.shouldBlockLaunch(
                now: ProcessInfo.processInfo.systemUptime,
                lastTriggerAt: lastMediaKeyAt
            ) else { return }
        }
        if !app.forceTerminate() {
            app.terminate()
        }
        openReplacementIfConfigured()
    }

    private func openReplacementIfConfigured() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReplacementLaunch > 1.0 else { return }
        lastReplacementLaunch = now

        let path = UserDefaults.standard.string(forKey: DefaultsKey.musicBlockReplacementPath) ?? ""
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        // The replacement must never be the app being blocked, or the two
        // settings would chase each other in a launch-and-kill loop.
        guard let replacementID = Bundle(url: url)?.bundleIdentifier,
              !Self.blockedBundleIDs.contains(replacementID),
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func installMediaKeyTap() {
        guard !eventTap.isRunning else { return }
        let systemDefined = CGEventType(rawValue: MusicLaunchSupport.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<MusicLaunchBlocker>.fromOpaque(userInfo).takeUnretainedValue()
            return blocker.handleMediaKeyEvent(type: type, event: event)
        }
        eventTap.start(
            tap: .cgSessionEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
    }

    private func removeMediaKeyTap() { eventTap.stop() }

    private func handleMediaKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            eventTap.reArm()
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == MusicLaunchSupport.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              MusicLaunchSupport.isMusicLaunchTrigger(subtype: Int(nsEvent.subtype.rawValue),
                                                      data1: nsEvent.data1)
        else { return Unmanaged.passUnretained(event) }
        lastMediaKeyAt = ProcessInfo.processInfo.systemUptime
        return Unmanaged.passUnretained(event)
    }
}
