// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// How long a pressed sleep lasts. Napping is a timed thing: the player
/// presses Sleep, the buddy dozes off, and it wakes up on its own after a
/// random stretch — a pet, not a light switch. Pure so the test harness can
/// pin the schedule the model runs on.
enum PetNapSchedule {
    /// A nap lasts 5–15 minutes. Energy keeps restoring at its own rate and
    /// still tops the buddy up long after a nap of this length.
    static func wakeDelay() -> TimeInterval {
        .random(in: 5 * 60...15 * 60)
    }

    /// Whether the buddy's nap is due to end at `now`. The wake time was
    /// chosen when sleep was pressed; a nil time means sleep was started by
    /// an older build and simply runs until woken or fully rested.
    static func shouldWake(sleeping: Bool, wakeAt: Date?, now: Date) -> Bool {
        guard sleeping, let wakeAt else { return false }
        return now >= wakeAt
    }
}
