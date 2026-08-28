// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// The buddy's growth curve, what care is worth, and what neglect costs.
/// Pure so the test harness can pin the pacing without an app around it.
///
/// Levelling used to be a flat 100 XP a rung on top of an idle drip of
/// 1 XP a minute: 60 XP an hour for leaving the app open, which walked a
/// buddy to its final form inside a day without the player touching it.
/// The ladder here is quadratic instead — reaching level `n + 1` costs
/// `50n² + 60n` XP in total, so every rung is a longer climb than the one
/// below it — and the drip only runs while the buddy is actually thriving.
enum PetLevelCurve {
    static let maxLevel = 99

    /// Stage 2 lands at Lv 12, the final form at Lv 30: weeks and months of
    /// care rather than an afternoon of idling.
    static let secondStageLevel = 12
    static let finalStageLevel = 30

    /// Total XP needed to reach `level` from a fresh buddy.
    static func totalXP(toReach level: Int) -> Double {
        let n = Double(max(0, min(maxLevel, level) - 1))
        return 50 * n * n + 60 * n
    }

    /// The level `xp` has bought. The inverse of `totalXP`, solved directly
    /// (`50n² + 60n - xp = 0`) rather than walking the ladder.
    static func level(for xp: Double) -> Int {
        let n = (-60 + (3600 + 200 * max(0, xp)).squareRoot()) / 100
        // The nudge keeps an exact threshold (110 XP -> Lv 2) from landing a
        // hair under its own boundary in binary floating point.
        return min(maxLevel, Int(n + 1e-9) + 1)
    }

    /// How far through the current level `xp` sits, 0...1.
    static func progress(for xp: Double) -> Double {
        let lv = level(for: xp)
        guard lv < maxLevel else { return 1 }
        let base = totalXP(toReach: lv)
        return min(1, max(0, (xp - base) / (totalXP(toReach: lv + 1) - base)))
    }

    /// The XP a level rung is worth, used for both progress and penalties.
    static func levelSpan(at level: Int) -> Double {
        level < maxLevel
            ? totalXP(toReach: level + 1) - totalXP(toReach: level)
            : totalXP(toReach: level) - totalXP(toReach: level - 1)
    }

    /// XP paid for care, per point of a stat that care actually restored.
    ///
    /// Buttons earn nothing on their own: feeding a full buddy or petting a
    /// maxed-out one restores nothing and so pays nothing. That caps a day's
    /// care XP at whatever the day's decay opened back up, which is what
    /// stops a level being farmed by holding down Pet.
    static func careXP(restored: Double) -> Double { max(0, restored) * 0.5 }

    /// Idle XP per second, and only while the buddy's mood is `.great`:
    /// 12 XP an hour for keeping it genuinely happy, nothing at all for
    /// leaving a neglected one running.
    static let bondXPPerSecond: Double = 12.0 / 3600

    /// Coins for each level reached. Rungs are rare now, so they pay better.
    static func levelUpCoins(for level: Int) -> Int { 20 * level }

    // MARK: Fainting

    /// How long hunger or happiness may sit at rock bottom before the buddy
    /// faints. Long enough that a night's sleep is never fatal.
    static let faintDelay: TimeInterval = 6 * 3600

    /// Coins to revive a buddy when the bag has no berry left.
    static let reviveCoins = 50

    /// XP left after a faint: a quarter of the rung it was standing on, and
    /// never past zero. Deep enough to sting — it can drop a level — and
    /// shallow enough that a bad week is not a wipe.
    static func xpAfterFaint(_ xp: Double) -> Double {
        max(0, xp - levelSpan(at: level(for: xp)) * 0.25)
    }
}
