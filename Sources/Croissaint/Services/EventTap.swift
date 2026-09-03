// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import CoreGraphics
import Foundation

/// One `CGEvent` tap on the main run loop, together with the run-loop source it
/// needs to deliver anything.
///
/// Standing a tap up is four steps (create, make a source, add the source,
/// enable) and taking it down is three (disable, remove the source, drop both
/// references). Every service that wanted a tap wrote all seven out by hand,
/// twenty-odd times over, which is twenty-odd chances to leave a run-loop
/// source attached to a tap that is already gone.
///
/// The C callback and its `userInfo` pointer are passed straight through, so a
/// service keeps its existing top-level callback and its own `Unmanaged`
/// round-trip — this owns the lifecycle, not the routing.
///
/// Taps that run on a thread of their own (the ones holding a lifecycle lock
/// and a `shouldStopTapThread` flag) keep their hand-written setup: they park
/// their source on a private run loop and have to coordinate with that thread's
/// teardown, which is a genuinely different lifecycle from this one.
final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// False for a tap the system disabled behind our back (Accessibility
    /// revoked and regranted, say). Such a tap never revives on its own, so
    /// callers rebuild instead of keeping the corpse.
    var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Creates the tap and starts delivery. Returns false when the system
    /// refuses one — in practice a missing Accessibility grant, which each
    /// caller reports its own way.
    @discardableResult
    func start(tap location: CGEventTapLocation = .cghidEventTap,
               place: CGEventTapPlacement = .headInsertEventTap,
               options: CGEventTapOptions = .defaultTap,
               eventsOfInterest: CGEventMask,
               callback: @escaping CGEventTapCallBack,
               userInfo: UnsafeMutableRawPointer?) -> Bool {
        stop()
        guard let created = CGEvent.tapCreate(tap: location,
                                              place: place,
                                              options: options,
                                              eventsOfInterest: eventsOfInterest,
                                              callback: callback,
                                              userInfo: userInfo)
        else { return false }

        tap = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    /// macOS disables a tap that stalls, and again whenever the session locks.
    /// Handlers call this from their own `.tapDisabledByTimeout` /
    /// `.tapDisabledByUserInput` branch, which is where each service also does
    /// whatever state-resetting its own feature needs.
    func reArm() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func stop() {
        // Invalidating the port releases it and kills its sources; the
        // hand-written teardowns that skipped it only got away with it because
        // they dropped the reference immediately afterwards anyway.
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    deinit { stop() }
}
