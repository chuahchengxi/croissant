// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import SwiftUI

// MARK: - Pixel sprites for moves

/// Every move particle is a tiny hand-drawn pixel map rendered once to a
/// CGImage and upscaled nearest-neighbour, so effects match the sprite art.
enum PetMovePixelArt {
    static func image(for style: PetMoveStyle) -> CGImage? {
        if let cached = cache.object(forKey: style.rawValue as NSString) {
            return cached
        }
        guard let image = render(style) else { return nil }
        cache.setObject(image, forKey: style.rawValue as NSString)
        return image
    }

    private static let cache = NSCache<NSString, CGImage>()

    private static func render(_ style: PetMoveStyle) -> CGImage? {
        let map: [String]
        let palette: [Character: CGColor]
        switch style {
        case .waterJet, .waterShuriken:
            palette = ["B": CGColor(srgbRed: 0.24, green: 0.56, blue: 0.96, alpha: 1),
                       "C": CGColor(srgbRed: 0.62, green: 0.85, blue: 1, alpha: 1)]
            map = style == .waterShuriken ? shuriken : droplet
        case .flameJet, .ember:
            palette = ["R": CGColor(srgbRed: 0.96, green: 0.42, blue: 0.12, alpha: 1),
                       "Y": CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)]
            map = ember
        case .bolt:
            palette = ["Y": CGColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 1),
                       "W": CGColor(srgbRed: 1, green: 1, blue: 0.85, alpha: 1)]
            map = bolt
        case .leafStorm:
            palette = ["G": CGColor(srgbRed: 0.36, green: 0.78, blue: 0.32, alpha: 1),
                       "L": CGColor(srgbRed: 0.65, green: 0.9, blue: 0.45, alpha: 1)]
            map = leaf
        case .psychicOrb, .auraSphere:
            palette = ["P": CGColor(srgbRed: 0.85, green: 0.45, blue: 0.95, alpha: 1),
                       "W": CGColor(srgbRed: 1, green: 0.9, blue: 1, alpha: 1)]
            map = orb
        case .shadowBall, .darkBurst:
            palette = ["D": CGColor(srgbRed: 0.3, green: 0.22, blue: 0.45, alpha: 1),
                       "P": CGColor(srgbRed: 0.6, green: 0.5, blue: 0.8, alpha: 1)]
            map = orb
        case .starBurst, .fairySparkle:
            palette = ["Y": CGColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: 1),
                       "P": CGColor(srgbRed: 1, green: 0.7, blue: 0.9, alpha: 1)]
            map = star
        case .coinToss:
            palette = ["Y": CGColor(srgbRed: 1, green: 0.8, blue: 0.15, alpha: 1),
                       "O": CGColor(srgbRed: 0.85, green: 0.55, blue: 0.05, alpha: 1)]
            map = coin
        case .singNotes:
            palette = ["P": CGColor(srgbRed: 0.95, green: 0.6, blue: 0.8, alpha: 1),
                       "W": CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]
            map = note
        case .boneToss:
            palette = ["W": CGColor(srgbRed: 0.98, green: 0.96, blue: 0.88, alpha: 1),
                       "G": CGColor(srgbRed: 0.8, green: 0.78, blue: 0.7, alpha: 1)]
            map = bone
        case .rockThrow, .sandPuff, .mudPuff:
            palette = ["B": CGColor(srgbRed: 0.62, green: 0.5, blue: 0.38, alpha: 1),
                       "G": CGColor(srgbRed: 0.8, green: 0.7, blue: 0.55, alpha: 1)]
            map = rock
        case .steelGlint:
            palette = ["W": CGColor(srgbRed: 0.85, green: 0.9, blue: 0.98, alpha: 1),
                       "B": CGColor(srgbRed: 0.55, green: 0.62, blue: 0.75, alpha: 1)]
            map = glint
        case .iceShard:
            palette = ["C": CGColor(srgbRed: 0.6, green: 0.9, blue: 1, alpha: 1),
                       "W": CGColor(srgbRed: 0.9, green: 0.98, blue: 1, alpha: 1)]
            map = shard
        case .poisonBubbles:
            palette = ["P": CGColor(srgbRed: 0.7, green: 0.4, blue: 0.85, alpha: 1),
                       "L": CGColor(srgbRed: 0.85, green: 0.65, blue: 0.95, alpha: 1)]
            map = bubble
        case .gustStreaks, .dragonPulse, .dragonDart:
            palette = ["C": CGColor(srgbRed: 0.55, green: 0.8, blue: 1, alpha: 1),
                       "V": CGColor(srgbRed: 0.7, green: 0.5, blue: 1, alpha: 1)]
            map = streak
        case .bugSwarm:
            palette = ["G": CGColor(srgbRed: 0.6, green: 0.75, blue: 0.25, alpha: 1),
                       "D": CGColor(srgbRed: 0.3, green: 0.35, blue: 0.15, alpha: 1)]
            map = bug
        case .impactBurst, .slashArc:
            palette = ["Y": CGColor(srgbRed: 1, green: 0.95, blue: 0.6, alpha: 1),
                       "W": CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)]
            map = impact
        case .heartBurst:
            palette = ["P": CGColor(srgbRed: 1, green: 0.45, blue: 0.6, alpha: 1)]
            map = heart
        }
        return PetMovePixelArt.render(map: map, palette: palette)
    }

    private static func render(map: [String], palette: [Character: CGColor]) -> CGImage? {
        let height = map.count
        let width = map.map(\.count).max() ?? 0
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.setShouldAntialias(false)
        for (row, line) in map.enumerated() {
            for (col, char) in line.enumerated() {
                guard let color = palette[char] else { continue }
                ctx.setFillColor(color)
                ctx.fill(CGRect(x: col, y: height - 1 - row, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }

    // 5-9px pixel maps, one character per pixel.
    private static let droplet = [
        "..C..",
        ".CBC.",
        "CBCBC",
        ".CBC.",
        "..C..",
    ]
    private static let shuriken = [
        "C..C..C",
        ".C.C.C.",
        "..CCC..",
        "CCCCCBC",
        "..CCC..",
        ".C.C.C.",
        "C..C..C",
    ]
    private static let ember = [
        ".Y.",
        "YRY",
        "RYR",
        ".R.",
    ]
    private static let bolt = [
        "..YWW",
        ".YWW.",
        "YWW..",
        "WY...",
        "Y....",
    ]
    private static let leaf = [
        "LL...",
        "GGLL.",
        ".GGGL",
        ".GG..",
        "G....",
    ]
    private static let orb = [
        ".PP.",
        "PWWP",
        "PWWP",
        ".PP.",
    ]
    private static let star = [
        "..Y..",
        ".YYY.",
        "YYYYY",
        ".YYY.",
        "..Y..",
    ]
    private static let coin = [
        ".YYY.",
        "YYOYY",
        "YOYOY",
        "YYOYY",
        ".YYY.",
    ]
    private static let note = [
        "..PPP",
        "..P.P",
        "..P..",
        "PPP..",
        "PPP..",
    ]
    private static let bone = [
        "W....W",
        "WWWWWW",
        "W....W",
    ]
    private static let rock = [
        ".GG.",
        "BGGB",
        "BBGG",
        ".BB.",
    ]
    private static let glint = [
        "W.",
        "WBW",
        ".W.",
    ]
    private static let shard = [
        "C.",
        "CWC",
        ".CW",
    ]
    private static let bubble = [
        ".LL.",
        "L..L",
        "L..L",
        ".LL.",
    ]
    private static let streak = [
        "C...",
        ".CV.",
        "..CV",
    ]
    private static let bug = [
        ".G.G",
        "GDGD",
        ".G.G",
    ]
    private static let impact = [
        "W.Y.W",
        ".YWY.",
        "YWWWY",
        ".YWY.",
        "W.Y.W",
    ]
    private static let heart = [
        ".P.P.",
        "PPPPP",
        "PPPPP",
        ".PPP.",
        "..P..",
    ]
}

// MARK: - Move effect view

struct PetMoveInstance: Identifiable {
    let id = UUID()
    let style: PetMoveStyle
    let facingLeft: Bool
}

/// A short particle burst: the buddy flings a handful of pixel sprites in its
/// facing direction with a little gravity and spin. Lives under a second,
/// runs only while playing, then removes itself.
struct PetMoveEffectView: View {
    let move: PetMoveInstance
    let onDone: () -> Void

    @State private var start = Date()

    private static let lifetime: Double = 0.85
    private static let count = 9

    private func burst(at date: Date) -> some View {
        Canvas { context, _ in
            let t = date.timeIntervalSince(start)
            guard t >= 0, t <= Self.lifetime,
                  let sprite = PetMovePixelArt.image(for: move.style)
            else { return }
            let progress = t / Self.lifetime
            let direction: CGFloat = move.facingLeft ? -1 : 1
            // One SwiftUI image for all particles, not one per particle.
            let particle = Image(decorative: sprite, scale: 1).interpolation(.none)
            for index in 0..<Self.count {
                let seed = Double(index)
                // Fan-out angles with per-particle speed and spin.
                let angle = (-0.55 + seed * 0.14) * .pi
                let speed = 46.0 + (seed.truncatingRemainder(dividingBy: 3)) * 16
                let x = direction * cos(angle) * speed * progress * 2.1
                let y = sin(angle) * speed * progress * 1.5 + 90 * progress * progress
                let scale = 2.0 + (seed.truncatingRemainder(dividingBy: 2))
                let size = CGFloat(sprite.width) * scale
                    * (move.style == .waterShuriken ? 1.4 : 1)
                let spin = move.style == .waterShuriken || move.style == .boneToss
                    ? Angle.degrees(t * 720 + seed * 60)
                    : .zero
                let opacity = progress > 0.75 ? (1 - progress) / 0.25 : 1
                var cx = context
                cx.opacity = opacity
                cx.translateBy(x: 30 + CGFloat(x), y: -6 + CGFloat(y))
                cx.rotate(by: spin)
                cx.draw(
                    particle,
                    in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
                )
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            burst(at: timeline.date)
        }
        .frame(width: 150, height: 90, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear {
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime + 0.05) {
                onDone()
            }
        }
    }
}
