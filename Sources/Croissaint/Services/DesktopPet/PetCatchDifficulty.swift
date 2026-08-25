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

    var label: String {
        switch self {
        case .common: return "Easy"
        case .wary: return "Wary"
        case .tough: return "Tough"
        case .legendary: return "Legendary"
        }
    }

    /// Final odds for a ball against this tier. Great Balls ×1.5, Ultra
    /// Balls ×2, capped at 95% — even a mythic never becomes a formality,
    /// and nothing is unwinnable.
    func odds(for kind: PetItemKind) -> Double {
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
