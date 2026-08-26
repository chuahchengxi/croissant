// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// One hand-drawn move particle: a pixel map, one character per pixel, and
/// the palette its characters name. `.` is transparent.
struct PetMoveSprite: Equatable {
    let map: [String]
    /// Keys are the map's characters; values are 0xRRGGBB.
    let palette: [Character: Int]
}

/// How one move flies. Same burst, different physics: without this every
/// move was the same nine-particle fan at the same speed, so two moves with
/// different art still read as one animation in a recoloured coat.
struct PetMoveFlight: Equatable {
    /// Fan-out speed, downward pull over the burst, and how wide the fan opens.
    var speed = 1.0
    var gravity = 1.0
    var spread = 1.0
    /// Particle spin in degrees per second, and size multiplier.
    var spin = 0.0
    var scale = 1.0
    var count = 9
}

/// The particle art every move flings, kept apart from the drawing code so
/// the test harness (pure Foundation, no AppKit) can hold the whole set to
/// its contract: every style draws its own sprite, and every sprite carries
/// enough colour to read as pixel art rather than a coloured blob.
///
/// Styles used to share maps — one orb stood in for psychic, aura, shadow and
/// dark; one streak for gust, dragon pulse and dragon dart — so a third of
/// the move list looked identical in flight, and each palette was two flat
/// colours. Sharing is now a test failure.
enum PetMoveArt {
    /// One flight profile per style, all distinct — a bolt snaps out flat and
    /// fast, a coin lobs and tumbles, bubbles drift up and hang. Numbers are
    /// multipliers on the burst in `PetMoveEffectView`; `.init()` is the
    /// original nine-particle fan.
    static func flight(for style: PetMoveStyle) -> PetMoveFlight {
        switch style {
        case .bolt:
            return PetMoveFlight(speed: 1.7, gravity: 0.15, spread: 0.45, scale: 1.1, count: 7)
        case .waterJet:
            return PetMoveFlight(speed: 1.35, gravity: 0.7, spread: 0.5, count: 11)
        case .waterShuriken:
            return PetMoveFlight(speed: 1.5, gravity: 0.35, spread: 0.35, spin: 720, scale: 1.4, count: 5)
        case .flameJet:
            return PetMoveFlight(speed: 1.25, gravity: -0.35, spread: 0.6, scale: 1.15, count: 10)
        case .ember:
            return PetMoveFlight(speed: 0.75, gravity: -0.55, spread: 1.15, scale: 0.9, count: 12)
        case .leafStorm:
            return PetMoveFlight(speed: 0.95, gravity: 0.25, spread: 1.3, spin: 220, count: 12)
        case .psychicOrb:
            return PetMoveFlight(speed: 0.7, gravity: -0.15, spread: 1.05, spin: 90, scale: 1.2, count: 6)
        case .shadowBall:
            return PetMoveFlight(speed: 0.65, gravity: 0.1, spread: 0.8, spin: -120, scale: 1.3, count: 5)
        case .darkBurst:
            return PetMoveFlight(speed: 1.1, gravity: 0.2, spread: 1.45, spin: -260, count: 10)
        case .starBurst:
            return PetMoveFlight(speed: 1.2, gravity: 0.5, spread: 1.5, spin: 300, count: 8)
        case .coinToss:
            return PetMoveFlight(speed: 0.9, gravity: 1.8, spread: 0.55, spin: 900, count: 6)
        case .singNotes:
            return PetMoveFlight(speed: 0.6, gravity: -0.75, spread: 0.95, spin: 60, count: 7)
        case .boneToss:
            return PetMoveFlight(speed: 1.05, gravity: 1.5, spread: 0.4, spin: 720, scale: 1.2, count: 4)
        case .rockThrow:
            return PetMoveFlight(speed: 1.0, gravity: 2.1, spread: 0.7, spin: 180, scale: 1.25, count: 5)
        case .steelGlint:
            return PetMoveFlight(speed: 1.45, gravity: 0.05, spread: 1.2, scale: 0.85, count: 8)
        case .fairySparkle:
            return PetMoveFlight(speed: 0.8, gravity: -0.45, spread: 1.6, spin: 150, scale: 0.95, count: 13)
        case .iceShard:
            return PetMoveFlight(speed: 1.55, gravity: 0.45, spread: 0.65, spin: 200, count: 9)
        case .poisonBubbles:
            return PetMoveFlight(speed: 0.55, gravity: -0.95, spread: 1.25, spin: 45, scale: 1.1, count: 11)
        case .gustStreaks:
            return PetMoveFlight(speed: 1.8, gravity: -0.1, spread: 0.85, scale: 1.05, count: 12)
        case .dragonPulse:
            return PetMoveFlight(speed: 0.85, gravity: 0, spread: 1.35, spin: 120, scale: 1.35, count: 6)
        case .auraSphere:
            return PetMoveFlight(speed: 1.15, gravity: -0.05, spread: 0.3, spin: 60, scale: 1.3, count: 4)
        case .bugSwarm:
            return PetMoveFlight(speed: 0.7, gravity: -0.25, spread: 1.7, spin: 400, scale: 0.9, count: 14)
        case .sandPuff:
            return PetMoveFlight(speed: 0.9, gravity: 0.85, spread: 1.4, spin: 90, count: 12)
        case .impactBurst:
            return PetMoveFlight(speed: 1.6, gravity: 0.6, spread: 1.55, scale: 1.15, count: 8)
        case .dragonDart:
            return PetMoveFlight(speed: 1.95, gravity: 0.1, spread: 0.25, spin: 30, count: 5)
        case .slashArc:
            return PetMoveFlight(speed: 1.4, gravity: 0.3, spread: 0.9, spin: -180, scale: 1.45, count: 3)
        case .mudPuff:
            return PetMoveFlight(speed: 0.65, gravity: 1.25, spread: 1.1, spin: 140, scale: 1.2, count: 7)
        case .heartBurst:
            return PetMoveFlight(speed: 0.75, gravity: -0.65, spread: 1.15, spin: 75, count: 10)
        }
    }

    static func sprite(for style: PetMoveStyle) -> PetMoveSprite {
        switch style {
        case .bolt:
            return PetMoveSprite(map: [
                "...AY",
                "..AYW",
                ".AYW.",
                "AYWYA",
                "..YWA",
                ".YWA.",
                "AY...",
            ], palette: ["W": 0xFFFDE8, "Y": 0xFFE23A, "A": 0xF29B1D])

        case .waterJet:
            return PetMoveSprite(map: [
                "..C..",
                ".CBC.",
                "CBWBC",
                "CBBDC",
                ".CDDC",
                "..D..",
            ], palette: ["W": 0xEAF9FF, "C": 0x8FD4FF, "B": 0x3D8BE8, "D": 0x1B4FA8])

        case .waterShuriken:
            return PetMoveSprite(map: [
                "C..C..C",
                ".CWCWC.",
                "..CWC..",
                "CWCDCWC",
                "..CWC..",
                ".CWCWC.",
                "C..C..C",
            ], palette: ["W": 0xF2FEFF, "C": 0x6FC6F5, "D": 0x14567F])

        case .flameJet:
            return PetMoveSprite(map: [
                "..Y..",
                ".YWY.",
                "OYWYO",
                "OYWYO",
                "ROYOR",
                "RRORR",
                ".RKR.",
            ], palette: ["W": 0xFFF6D2, "Y": 0xFFD336, "O": 0xF5751A, "R": 0xC42A12,
                         "K": 0x5E1608])

        case .ember:
            return PetMoveSprite(map: [
                ".Y.",
                "YOY",
                "ORO",
                ".K.",
            ], palette: ["Y": 0xFFDE5C, "O": 0xF88B25, "R": 0xD03A14, "K": 0x4A2418])

        case .leafStorm:
            return PetMoveSprite(map: [
                "...GL",
                "..GLL",
                ".GVLL",
                "GVGL.",
                "DGG..",
                "D....",
            ], palette: ["L": 0xB7EB63, "G": 0x4EAE38, "V": 0xE8FBC0, "D": 0x1F5E22])

        case .psychicOrb:
            return PetMoveSprite(map: [
                ".HPPH.",
                "HPVVPH",
                "PVWWVP",
                "PVWWVP",
                "HPVVPH",
                ".HPPH.",
            ], palette: ["W": 0xFFF0FF, "V": 0xC26BF0, "P": 0x8E2FD4, "H": 0xF3B6FF])

        case .shadowBall:
            return PetMoveSprite(map: [
                "L..VL.",
                ".VPKPV",
                "VPKKKP",
                "VPKKKP",
                ".VPKPV",
                "L.VL..",
            ], palette: ["K": 0x160B26, "P": 0x452063, "V": 0x7A47A8, "L": 0xC69AE6])

        case .darkBurst:
            return PetMoveSprite(map: [
                "K..K.",
                ".KPK.",
                "KPIPK",
                ".KPK.",
                ".K..K",
            // Lifted off black: a near-black particle over a dark desktop is
            // an invisible move.
            ], palette: ["K": 0x2A1B3D, "P": 0x5B3E86, "I": 0xA07BD8])

        case .starBurst:
            return PetMoveSprite(map: [
                "..O..",
                ".OYO.",
                "OYWYO",
                ".OYO.",
                "..O..",
            ], palette: ["W": 0xFFFFF2, "Y": 0xFFDE55, "O": 0xF0921F])

        case .coinToss:
            return PetMoveSprite(map: [
                ".BYB.",
                "BYWYB",
                "YWOWY",
                "BYWYB",
                ".BYB.",
            ], palette: ["W": 0xFFF6C9, "Y": 0xFFC523, "O": 0xE08A07, "B": 0x8A5306])

        case .singNotes:
            return PetMoveSprite(map: [
                "..WPP",
                "..WP.",
                "..M..",
                "..M..",
                "MMM..",
                "RMM..",
            ], palette: ["W": 0xFFFFFF, "P": 0xFF9AD5, "M": 0xE0479F, "R": 0x8E1F5E])

        case .boneToss:
            return PetMoveSprite(map: [
                "WC..CW",
                "WWGGWW",
                "WC..CW",
            ], palette: ["W": 0xFFFDF2, "C": 0xE4DCC4, "G": 0xA79C82])

        case .rockThrow:
            return PetMoveSprite(map: [
                ".TTB.",
                "TGGTB",
                "TGGGB",
                "BTGBB",
                ".BBB.",
            ], palette: ["T": 0xC7A176, "G": 0x8C6842, "B": 0x4E3722])

        case .steelGlint:
            return PetMoveSprite(map: [
                "S...S",
                ".WPW.",
                "..P..",
                ".WPW.",
                "S...S",
            ], palette: ["W": 0xFFFFFF, "P": 0xB9C8DB, "S": 0x5D6E85])

        case .fairySparkle:
            return PetMoveSprite(map: [
                "M.P.M",
                ".PWP.",
                "PWWWP",
                ".PWP.",
                "M.P.M",
            ], palette: ["W": 0xFFFFFF, "P": 0xFFA8D8, "M": 0x9BE8D2])

        case .iceShard:
            return PetMoveSprite(map: [
                "..W.",
                ".WCW",
                "WCCB",
                "WCCB",
                ".WCB",
                "..B.",
            ], palette: ["W": 0xF4FEFF, "C": 0x9BE6FA, "B": 0x3A87C7])

        case .poisonBubbles:
            return PetMoveSprite(map: [
                ".PP..V",
                "PWWP.V",
                "PWWP..",
                ".PP.VV",
                "..V.V.",
            ], palette: ["W": 0xE8C4FF, "P": 0x9B34C9, "V": 0x5C1580])

        case .gustStreaks:
            return PetMoveSprite(map: [
                "...CWW",
                ".CWWC.",
                "CWWC..",
                "..BCWW",
            ], palette: ["W": 0xFFFFFF, "C": 0xC9EEFF, "B": 0x74B8DC])

        case .dragonPulse:
            return PetMoveSprite(map: [
                ".VVVV.",
                "VCWWCV",
                "VC..CV",
                "VC..CV",
                "VCWWCV",
                ".VVVV.",
            ], palette: ["W": 0xE9FDFF, "C": 0x53D8F0, "V": 0x7A44E0])

        case .auraSphere:
            return PetMoveSprite(map: [
                ".HAAH.",
                "HAWWAH",
                "AWCCWA",
                "ACCCCA",
                "HACCAH",
                ".HAAH.",
            ], palette: ["W": 0xFFFFFF, "C": 0x1E86D8, "A": 0x63C2F5, "H": 0xC9EEFF])

        case .bugSwarm:
            return PetMoveSprite(map: [
                ".G.G.",
                "GDDDG",
                ".DRD.",
                "G.D.G",
            ], palette: ["G": 0x9BC53D, "D": 0x3E4A18, "R": 0xD94F2B])

        case .sandPuff:
            return PetMoveSprite(map: [
                ".TT..P",
                "TSST.P",
                "TSSSTP",
                ".TTT..",
            ], palette: ["S": 0xF3E2B0, "T": 0xD3B172, "P": 0x9A7B45])

        case .impactBurst:
            return PetMoveSprite(map: [
                "Y..O..Y",
                ".O.W.O.",
                "OWWWWWO",
                ".O.W.O.",
                "Y..O..Y",
            ], palette: ["W": 0xFFFFFF, "O": 0xFFD35E, "Y": 0xF08A2A])

        case .dragonDart:
            return PetMoveSprite(map: [
                "C....",
                "WC...",
                ".WCV.",
                "..WCV",
                ".WCV.",
                "WC...",
                "C....",
            ], palette: ["W": 0xF0FBFF, "C": 0x4FD2E8, "V": 0x6A3BD1])

        case .slashArc:
            return PetMoveSprite(map: [
                "...CW",
                "..CWW",
                ".CWW.",
                "CWW..",
                "RWW..",
                "R....",
            ], palette: ["W": 0xFFFFFF, "C": 0xB8F1FF, "R": 0xE05B7A])

        case .mudPuff:
            return PetMoveSprite(map: [
                ".MM..",
                "MOOM.",
                "MOOOM",
                ".MTM.",
            ], palette: ["O": 0x7A5A2E, "M": 0x412A12, "T": 0xB79A63])

        case .heartBurst:
            return PetMoveSprite(map: [
                ".P.P.",
                "PWPPP",
                "RPPPR",
                ".RPR.",
                "..R..",
            ], palette: ["W": 0xFFE3EE, "P": 0xFF5D86, "R": 0xC01F46])
        }
    }
}
