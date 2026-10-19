// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// Stands in for the fork's `EventTap` wrapper in fixtures that compile a
/// service's tap handlers on their own. It records re-arms so a fixture can
/// still tell a recovered tap from one left disabled.
final class EventTapStub {
    var isRunning = false
    private(set) var reArmCount = 0

    func reArm() { if isRunning { reArmCount += 1 } }
    func stop() { isRunning = false }
}
