// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

enum PetItemKind: String, Codable, CaseIterable {
    case pokeBall
    case greatBall
    case ultraBall
    case berry
    case everStone

    var displayName: String {
        switch self {
        case .pokeBall: return "Poké Ball"
        case .greatBall: return "Great Ball"
        case .ultraBall: return "Ultra Ball"
        case .berry: return "Oran Berry"
        case .everStone: return "Ever Stone"
        }
    }
}

