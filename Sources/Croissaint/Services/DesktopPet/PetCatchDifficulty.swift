// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// How hard a wild pokemon is to catch, derived from its PokeAPI capture
/// rate. A Poké Ball no longer one-shots everything: mythicals shrug it off
/// at ~10%, while everyday bugs still land easily. Better balls multiply the
/// species' base odds, and a pity counter guarantees progress after a run
/// of misses so bad aim can't hard-stall an encounter.
enum PetCatchTier {
    case common      // capture_rate >= 190 (Caterpie, Pikachu…)
    case wary        // 90–189 (Pikachu-line peers, starters' first stage)
    case tough       // 30–89 (pseudo-legendaries, Charizard, Snorlax…)
    case legendary   // < 30 (Mewtwo, the birds, the moons and swords…)

    static func tier(captureRate: Int) -> PetCatchTier {
        switch captureRate {
        case ..<30: return .legendary
        case ..<90: return .tough
        case ..<190: return .wary
        default: return .common
        }
    }

    static func tier(for dexID: Int) -> PetCatchTier {
        tier(captureRate: speciesCaptureRate(for: dexID))
    }

    /// Base odds with a plain Poké Ball.
    var baseOdds: Double {
        switch self {
        case .common: return 0.75
        case .wary: return 0.52
        case .tough: return 0.30
        case .legendary: return 0.10
        }
    }

    /// Misses after which the next hit catch is guaranteed — scales with
    /// difficulty so legendary stakeouts stay stakeouts.
    var pityMisses: Int {
        switch self {
        case .common: return 2
        case .wary: return 3
        case .tough: return 4
        case .legendary: return 5
        }
    }

    /// Payout for transferring a spare copy of this tier — every rank pays
    /// differently, and higher ranks pay in better gear.
    var transferRewards: [(kind: PetItemKind, count: Int)] {
        switch self {
        case .common: return [(.pokeBall, 2), (.berry, 2)]
        case .wary: return [(.pokeBall, 3), (.berry, 3)]
        case .tough: return [(.greatBall, 2), (.berry, 4)]
        case .legendary: return [(.ultraBall, 2), (.everStone, 1), (.berry, 5)]
        }
    }

    /// XP a catch of this tier is worth. Landing a legendary is most of a
    /// day's care XP; a Caterpie is a nice extra and no more.
    var catchXP: Double {
        switch self {
        case .common: return 8
        case .wary: return 14
        case .tough: return 25
        case .legendary: return 60
        }
    }

    var transferCoins: Int {
        switch self {
        case .common: return 10
        case .wary: return 25
        case .tough: return 50
        case .legendary: return 150
        }
    }

    var label: String {
        switch self {
        case .common: return "Easy"
        case .wary: return "Wary"
        case .tough: return "Tough"
        case .legendary: return "Legendary"
        }
    }

    /// The weakest ball that can hold this tier at all: everyday species
    /// take any ball, tough ones need at least a Great Ball, and legendaries
    /// only stay in an Ultra Ball.
    var requiredBall: PetItemKind {
        switch self {
        case .common, .wary: return .pokeBall
        case .tough: return .greatBall
        case .legendary: return .ultraBall
        }
    }

    private static func rank(of kind: PetItemKind) -> Int {
        switch kind {
        case .pokeBall: return 0
        case .greatBall: return 1
        case .ultraBall: return 2
        default: return -1
        }
    }

    func canCatch(with kind: PetItemKind) -> Bool {
        Self.rank(of: kind) >= Self.rank(of: requiredBall)
    }

    /// Final odds for a ball against this tier. Great Balls ×1.5, Ultra
    /// Balls ×2, capped at 95% — even a mythic never becomes a formality,
    /// and nothing is unwinnable. A ball below the tier's required ball
    /// cannot catch at all: zero odds, and the pity counter routes through
    /// this too, so no guarantee ever overrides the gate.
    func odds(for kind: PetItemKind) -> Double {
        guard canCatch(with: kind) else { return 0 }
        let multiplier: Double
        switch kind {
        case .pokeBall: multiplier = 1.0
        case .greatBall: multiplier = 1.5
        case .ultraBall: multiplier = 2.0
        default: multiplier = 1.0
        }
        return min(0.95, baseOdds * multiplier)
    }
}
