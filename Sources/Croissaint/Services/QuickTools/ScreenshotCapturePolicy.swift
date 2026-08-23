// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Decides which of this process's windows ScreenCaptureKit must exclude.
/// Protected IDs are intersected with the actual own IDs from the same
/// shareable-content snapshot, so stale window numbers cannot affect another app.
enum ScreenshotCapturePolicy {
    static func excludedWindowIDs(hideCroissaintWindows: Bool,
                                  ownWindowIDs: Set<CGWindowID>,
                                  protectedWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        hideCroissaintWindows ? ownWindowIDs : ownWindowIDs.intersection(protectedWindowIDs)
    }

    static func canPickWindow(_ windowID: CGWindowID,
                              isOwnWindow: Bool,
                              hideCroissaintWindows: Bool,
                              protectedWindowIDs: Set<CGWindowID>) -> Bool {
        !isOwnWindow
            || (!hideCroissaintWindows && !protectedWindowIDs.contains(windowID))
    }
}
