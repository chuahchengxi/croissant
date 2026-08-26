// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import SwiftUI

// MARK: - Pixel sprites for moves

/// Every move particle is a tiny hand-drawn pixel map rendered once to a
/// CGImage and upscaled nearest-neighbour, so effects match the sprite art.
/// The maps and palettes live in `PetMoveArt`, which the unit harness holds
/// to one sprite per style.
enum PetMovePixelArt {
    static func image(for style: PetMoveStyle) -> CGImage? {
        if let cached = cache.object(forKey: style.rawValue as NSString) {
            return cached
        }
        guard let image = render(PetMoveArt.sprite(for: style)) else { return nil }
        cache.setObject(image, forKey: style.rawValue as NSString)
        return image
    }

    private static let cache = NSCache<NSString, CGImage>()

    private static func render(_ sprite: PetMoveSprite) -> CGImage? {
        let height = sprite.map.count
        let width = sprite.map.map(\.count).max() ?? 0
        guard width > 0, height > 0,
              let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.setShouldAntialias(false)
        for (row, line) in sprite.map.enumerated() {
            for (col, char) in line.enumerated() {
                guard let hex = sprite.palette[char] else { continue }
                ctx.setFillColor(CGColor(
                    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1
                ))
                ctx.fill(CGRect(x: col, y: height - 1 - row, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }
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

    private func burst(at date: Date) -> some View {
        Canvas { context, _ in
            let t = date.timeIntervalSince(start)
            guard t >= 0, t <= Self.lifetime,
                  let sprite = PetMovePixelArt.image(for: move.style)
            else { return }
            let progress = t / Self.lifetime
            let direction: CGFloat = move.facingLeft ? -1 : 1
            // Speed, pull, fan width, spin and size all come from the style's
            // own flight profile, so no two moves throw the same way.
            let flight = PetMoveArt.flight(for: move.style)
            // One SwiftUI image for all particles, not one per particle.
            let particle = Image(decorative: sprite, scale: 1).interpolation(.none)
            let step = 1.12 / Double(max(1, flight.count - 1))
            for index in 0..<flight.count {
                let seed = Double(index)
                // Fan-out angles with per-particle speed and spin.
                let angle = (-0.56 + seed * step) * .pi * flight.spread
                let speed = (46.0 + (seed.truncatingRemainder(dividingBy: 3)) * 16) * flight.speed
                let x = direction * cos(angle) * speed * progress * 2.1
                let y = sin(angle) * speed * progress * 1.5
                    + 90 * progress * progress * flight.gravity
                let scale = (2.0 + (seed.truncatingRemainder(dividingBy: 2))) * flight.scale
                let size = CGFloat(sprite.width) * CGFloat(scale)
                let spin = flight.spin == 0
                    ? Angle.zero
                    : Angle.degrees(t * flight.spin + seed * 60)
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
