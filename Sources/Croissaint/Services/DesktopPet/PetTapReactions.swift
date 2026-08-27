// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// The buddy's reaction to being petted (a click on the desktop buddy):
/// one short springy body animation per tap, so petting reads as touching
/// a creature instead of clicking a bitmap. Pure math over elapsed seconds
/// — the view's timeline just evaluates it, and tests can pin the shapes.
enum PetTapReaction: CaseIterable {
    /// Squash flat under the touch, spring back with a decaying wobble.
    case bounce
    /// Happy shimmy: a quick side-to-side tail-wag of the whole body.
    case wiggle
    /// Two little decaying delight hops with a lean into each one.
    case hop

    /// How long a reaction owns the body. Amplitudes decay hard enough
    /// that the cutoff lands within a pixel of rest — no visible snap.
    static let duration: Double = 0.9

    /// Deterministic per-tap pick that never repeats the previous tap's
    /// reaction: pulses walk the cases with a +2 stride (coprime with the
    /// count), offset by species so different buddies don't sync up.
    static func pick(pulse: Int, seed: Int) -> PetTapReaction {
        let all = allCases
        return all[abs(pulse * 2 + seed) % all.count]
    }

    /// Vertical shift in points for a body of `height` (negative = up).
    func offsetY(at t: Double, height: Double) -> Double {
        guard (0..<Self.duration).contains(t) else { return 0 }
        switch self {
        case .bounce: return 0
        case .wiggle: return -2 * abs(sin(t * 11)) * exp(-3 * t)
        case .hop: return -0.22 * height * abs(sin(t * .pi / 0.42)) * exp(-2.6 * t)
        }
    }

    /// Body tilt in degrees, mirrored with the buddy's facing so the
    /// shimmy leads with the cheek that was petted.
    func rotation(at t: Double, facingLeft: Bool) -> Double {
        guard (0..<Self.duration).contains(t) else { return 0 }
        let dir: Double = facingLeft ? 1 : -1
        switch self {
        case .bounce: return 0
        case .wiggle: return dir * 14 * exp(-3.5 * t) * sin(t * 22)
        case .hop: return dir * 6 * exp(-2.5 * t) * sin(t * 7.5)
        }
    }

    /// Bottom-anchored squash & stretch. The press starts fully squashed
    /// (bounce begins at 0.70) and springs past rest on the way back.
    func scaleY(at t: Double) -> Double {
        guard (0..<Self.duration).contains(t) else { return 1 }
        switch self {
        case .bounce: return 1 - 0.30 * exp(-4 * t) * cos(t * 24)
        case .wiggle: return 1
        // Stretches on the way up, squashes between hops.
        case .hop: return 1 + 0.06 * exp(-2.6 * t) * sin(t * .pi / 0.42)
        }
    }

    /// The body fattens as it flattens (and thins as it stretches), so the
    /// squash reads as a soft creature, not a shrinking image.
    func scaleX(at t: Double) -> Double {
        1 + 0.6 * (1 - scaleY(at: t))
    }
}
