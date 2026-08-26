// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import CoreGraphics

/// Uniform visual sizing for pet sprites.
///
/// PokeAPI sources mix tight-canvas animated GIFs (gen 1–5) with 96×96
/// static PNGs (gen 6+) whose artwork occupies wildly different fractions
/// of its canvas, so two species shown at the same display height could
/// read as completely different sizes. Every render path measures the
/// opaque bounding box of a sprite once and applies a single bottom-anchored
/// scale so the VISIBLE artwork lands on a common, deliberately small
/// fraction of the display box — details intact, no giant tiny-monsters.
///
/// The scale must wrap sprite AND overlays together (eyelids, leg slices),
/// which every call site does; a uniform transform can never drift the
/// overlays off the art.
enum PetSpriteMetrics {
    /// Fraction of the display box the visible artwork targets.
    static let targetFill: Double = 0.94
    /// Clamps keep extremes sane: never inflate a padded sprite into a blur,
    /// never shrink a tight one into a speck.
    static let minScale: Double = 0.8
    static let maxScale: Double = 1.6
    /// Wide species are clamped by breadth too: visible width may not exceed
    /// this multiple of the display height.
    static let maxWidthOverHeight: Double = 1.35

    private static var scales: [Int: Double] = [:]

    struct Fill {
        let widthFraction: Double
        let heightFraction: Double
    }

    /// Bottom-anchored scale that normalizes `frames`' artwork. Returns 1
    /// while frames are unavailable so callers render unchanged until the
    /// sprite decodes; the value memoizes per species after that.
    static func scale(for id: Int, frames: [CGImage]) -> Double {
        if let known = scales[id] { return known }
        guard let frame = frames.first, let fill = fillRatio(of: frame) else { return 1 }
        let aspect = Double(frame.width) / Double(frame.height)
        var s = targetFill / fill.heightFraction
        if fill.widthFraction > 0 {
            s = min(s, maxWidthOverHeight / (fill.widthFraction * aspect))
        }
        s = min(max(s, minScale), maxScale)
        scales[id] = s
        return s
    }

    /// Fractions of the canvas occupied by non-transparent pixels,
    /// measured on a small downsampled copy (a full-dex scan must stay cheap).
    static func fillRatio(of image: CGImage) -> Fill? {
        let box = 64
        let w: Int
        let h: Int
        if image.width >= image.height {
            w = box
            h = max(1, Int((Double(image.height) / Double(image.width)) * Double(box)))
        } else {
            h = box
            w = max(1, Int((Double(image.width) / Double(image.height)) * Double(box)))
        }
        guard
            let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w {
                if pixels[(y * w + x) * 4 + 3] >= 16 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return Fill(
            widthFraction: Double(maxX - minX + 1) / Double(w),
            heightFraction: Double(maxY - minY + 1) / Double(h)
        )
    }

    /// Test hook.
    static func reset() {
        scales.removeAll()
    }
}
