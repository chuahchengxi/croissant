// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// Sleep is a performance, not a still image.
///
/// On top of the tip-over nap pose (`PetAnimationPackSupport.sleepPose`) and
/// the shut lids, a sleeping buddy gets a whole body routine driven purely
/// from the wall clock, so every re-render agrees without any timers:
///
///  * **Breath groups** — breathing comes in waves: a few deeper breaths,
///    then lighter ones, the way real sleep breathes. Amplitude is
///    modulated by a slow second sine instead of a flat constant.
///  * **Dream twitches** — every 9–17 s (seeded per species) the buddy
///    kicks in its sleep: a short decaying jolt of lift, sideways shift
///    and tilt, alternating direction each cycle; a third of cycles double-
///    twitch with a counter-jerk.
///  * **Settling shifts** — every ~24–42 s the buddy re-settles its pose,
///    easing a few degrees of extra tilt toward a new seeded target with
///    smoothstep interpolation, so it never jumps between samples.
///
/// Everything is deterministic in `(time, seed)` — same inputs, same pose —
/// which is what lets it stay pure and pinned by tests.
enum PetSleepChoreography {
    struct Pose: Equatable {
        /// Upward body lift in points (breathing + dream kick).
        var yOffset: Double = 0
        /// Sideways drift in points (dream kick only).
        var xOffset: Double = 0
        /// Extra tilt in degrees (settling shift + dream kick).
        var angle: Double = 0
        /// Multiplicative scale (1 = neutral), gait-flavoured base included.
        var breathScale: Double = 1

        static let awake = Pose()
    }

    /// Full routine for one buddy. `seed` should be stable per species
    /// (dex id) so each buddy sleeps with its own rhythm.
    static func pose(at t: Double, seed: Int, gaitClass: Int) -> Pose {
        // Base scale keeps the squat-species squish from the old formula;
        // breathing then rides in waves rather than at a fixed depth, with
        // the current sleep style flavouring depth, rocking and ripple.
        let base: Double = gaitClass == 0 ? 0.965 : 1.0
        let style = styleParams(at: t, seed: seed)
        let groupModulation = 0.55 + 0.45 * sin(t * (2 * .pi / 23) + phi(seed, 1))
        let amplitude = 0.03 * style.breathDepth * groupModulation
        var breath = base + amplitude * sin(t * (2 * .pi / 1.9) + phi(seed, 2))
        // Purr ripple: a tiny fast flutter layered onto the breath.
        breath += style.ripple * sin(t * (2 * .pi / 0.45) + phi(seed, 8))

        // Restless rocking: a slow continuous sway, gone in calmer styles.
        let sway = style.sway * sin(t * (2 * .pi / 3.1) + phi(seed, 9))

        let kick = twitchOffset(at: t, seed: seed, scale: style.twitch)
        return Pose(
            yOffset: kick.y,
            xOffset: kick.x + sway,
            angle: settleAngle(at: t, seed: seed) + kick.angle,
            breathScale: breath
        )
    }

    // MARK: - Sleep styles

    /// One nap is several animations, not one: every 40–65 s the buddy moves
    /// to the next style in its own seeded rotation — calm breathing, deep
    /// slow breaths, restless rocking with bigger kicks, or a purring
    /// flutter. Parameters crossfade over the first seconds of each block so
    /// the pose stays continuous at every hand-over.
    struct StyleParams: Equatable {
        var breathDepth: Double   // multiplier on breath amplitude
        var ripple: Double        // fast flutter amplitude (scale units)
        var sway: Double          // rocking amplitude in points
        var twitch: Double        // multiplier on dream-kick travel
    }

    /// calm, deep, restless, purr.
    static let sleepStyles: [StyleParams] = [
        StyleParams(breathDepth: 0.6, ripple: 0, sway: 0, twitch: 0.7),
        StyleParams(breathDepth: 1.0, ripple: 0, sway: 0, twitch: 0.5),
        StyleParams(breathDepth: 0.45, ripple: 0, sway: 0.9, twitch: 1.3),
        StyleParams(breathDepth: 0.55, ripple: 0.004, sway: 0, twitch: 0.8),
    ]

    /// Which style a given block of the nap plays, per species: a seeded
    /// offset and stride walk the style table, so every species owns its own
    /// rotation (a stride of 2 alternates two styles; 1 or 3 visits all four).
    static func styleIndex(block: Int, seed: Int) -> Int {
        let offset = abs(seed) % sleepStyles.count
        let stride = 1 + abs(seed / 7) % 3
        return (offset + block * stride) % sleepStyles.count
    }

    private static func styleParams(at t: Double, seed: Int) -> StyleParams {
        let period = 40 + phi(seed, 10) * 25
        let block = Int(floor(t / period))
        let into = t - Double(block) * period
        let current = sleepStyles[styleIndex(block: max(0, block), seed: seed)]
        // Crossfade from the previous block's style over the first 5 s.
        let fade = 5.0
        guard into < fade, block > 0 else { return current }
        let previous = sleepStyles[styleIndex(block: block - 1, seed: seed)]
        let f = into / fade
        let eased = f * f * (3 - 2 * f)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * eased }
        return StyleParams(
            breathDepth: mix(previous.breathDepth, current.breathDepth),
            ripple: mix(previous.ripple, current.ripple),
            sway: mix(previous.sway, current.sway),
            twitch: mix(previous.twitch, current.twitch)
        )
    }

    // MARK: - Dream twitches

    /// One cycle's kick, evaluated inside its short window only. `scale`
    /// (from the active sleep style) stretches the travel, never the tilt —
    /// the tilt budget is what keeps the pose continuity guarantee.
    private static func twitchOffset(
        at t: Double, seed: Int, scale: Double = 1
    ) -> (y: Double, x: Double, angle: Double) {
        let period = 9 + phi(seed, 3) * 8          // 9–17 s between dreams
        let phase = phi(seed, 4)
        let cycle = floor((t + phase * period) / period)
        let u = t - (cycle - phase) * period       // seconds into this cycle

        guard u >= 0 else { return (0, 0, 0) }
        let window = 0.55
        let direction: Double = cycle.truncatingRemainder(dividingBy: 2) == 0 ? 1 : -1

        var envelope = 0.0
        if u < window {
            envelope = sin(.pi * u / window)
        } else if doubles(for: cycle, seed: seed),
                  u >= window + 0.18, u < window * 2 + 0.18 {
            // A third of dreams get a counter-jerk shortly after the first
            // kick; its window starts where its sine is zero, so the pose
            // never snaps into it.
            envelope = -sin(.pi * (u - window - 0.18) / window)
        }
        guard envelope != 0 else { return (0, 0, 0) }

        return (
            y: -direction * 1.6 * scale * envelope, // negative = upward hop
            x: -direction * 1.1 * scale * envelope,
            angle: direction * (1.8 * envelope)
        )
    }

    private static func doubles(for cycle: Double, seed: Int) -> Bool {
        phi(seed, 90 + abs(Int(cycle)) % 40) < 0.35
    }

    // MARK: - Settling shifts

    /// Slow re-settling: the buddy eases toward a new seeded tilt target
    /// every 24–42 s. Interpolating between consecutive targets with
    /// smoothstep means the angle is continuous everywhere by construction.
    private static func settleAngle(at t: Double, seed: Int) -> Double {
        let period = 24 + phi(seed, 6) * 18
        let k = floor(t / period)
        let frac = t / period - k
        let eased = frac * frac * (3 - 2 * frac)   // smoothstep
        let current = (phi(seed, 7 + abs(Int(k)) % 200) - 0.5) * 12
        // The block eases from the PREVIOUS block's target ((k-1) mod 200) to
        // its own; anything else snaps at every block boundary.
        let previous = (phi(seed, 7 + (abs(Int(k)) + 199) % 200) - 0.5) * 12
        return previous + (current - previous) * eased
    }

    // MARK: - Dream bubble flavour

    /// What the buddy dreams about, picked stably from its identity and the
    /// puff count — the caller renders it as an occasional pastel bubble
    /// among the plain z's.
    static let dreamSymbols = ["✦", "♪", "♡", "☁"]

    static func dreamSymbol(seed: Int, cycle: Int) -> String {
        dreamSymbols[abs(seed &+ cycle * 7) % dreamSymbols.count]
    }

    /// Every n-th drifting z becomes a dream bubble instead.
    static func dreamEvery(seed: Int) -> Int {
        3 + abs(seed) % 3
    }

    // MARK: - Hashing

    /// Deterministic pseudo-random in [0, 1) from an integer channel — the
    /// classic sin-hash; good enough for sleep, stable across runs.
    static func phi(_ seed: Int, _ channel: Int) -> Double {
        let v = sin(Double(seed) * 269.5 + Double(channel) * 127.1) * 43758.5453
        return v - v.rounded(.down)
    }
}
