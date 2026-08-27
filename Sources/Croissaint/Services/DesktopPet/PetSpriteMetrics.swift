// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import CoreGraphics

/// Uniform visual sizing for pet sprites.
///
/// PokeAPI sources mix tight-canvas animated GIFs (gen 1–5) with 96×96
/// static PNGs (gen 6+) whose artwork occupies wildly different fractions
/// of its canvas — and sits off-centre inside it, with up to a third of the
/// canvas empty below the feet. Every render path measures the opaque
/// bounding box of a sprite once and applies a single placement (scale +
/// re-centring shift) so the VISIBLE artwork lands on a common fraction of
/// the display box, centred — details intact, no giant tiny-monsters, no
/// buddies hugging one edge of their card.
///
/// The placement must wrap sprite AND overlays together (eyelids, leg
/// slices), which every call site does; a uniform transform can never drift
/// the overlays off the art.
enum PetSpriteMetrics {
    /// Fraction of the display box the visible artwork targets.
    static let targetFill: Double = 0.94
    /// Clamps keep extremes sane. Gen 6+ PNGs fill as little as ~35% of
    /// their canvas, so the cap must reach targetFill/0.35 — pixel art with
    /// nearest-neighbour scaling just gets chunkier, never blurry.
    static let minScale: Double = 0.8
    static let maxScale: Double = 2.7
    /// Wide species are clamped by breadth too: visible width may not exceed
    /// this multiple of the display height.
    static let maxWidthOverHeight: Double = 1.35

    /// How to draw one species' artwork inside its display box.
    struct Placement {
        let scale: Double
        /// Shift that moves the visible artwork's centre onto the canvas
        /// centre, as fractions of the displayed canvas width/height
        /// (SwiftUI signs: positive x = right, positive y = down).
        let centerDX: Double
        let centerDY: Double
        /// Transparent canvas below the artwork, as a fraction of canvas
        /// height — the desktop buddy sinks by this so feet touch ground.
        let bottomMargin: Double
        /// The visible artwork's own aspect (width over height). The sleep
        /// tip-over must judge the real body, not the padded canvas.
        let artWidthOverHeight: Double
        /// Height the artwork occupies in the display box after scaling,
        /// as a fraction of the box.
        let visibleHeightFraction: Double
    }

    /// Render-unchanged placement for sprites that haven't decoded yet.
    static let identity = Placement(
        scale: 1, centerDX: 0, centerDY: 0, bottomMargin: 0,
        artWidthOverHeight: 1, visibleHeightFraction: 1
    )

    private static var placements: [Int: Placement] = [:]

    struct Fill {
        let widthFraction: Double
        let heightFraction: Double
        /// Bounding-box centre as canvas fractions, y measured top-down.
        let centerX: Double
        let centerY: Double
        /// Empty canvas below the artwork, fraction of canvas height.
        let bottomMargin: Double
    }

    /// Convenience for callers that only scale (desktop buddy pose math).
    static func scale(for id: Int, frames: [CGImage]) -> Double {
        placement(for: id, frames: frames).scale
    }

    /// Placement that normalizes `frames`' artwork. Returns `identity`
    /// while frames are unavailable so callers render unchanged until the
    /// sprite decodes; the value memoizes per species after that.
    static func placement(for id: Int, frames: [CGImage]) -> Placement {
        if let known = placements[id] { return known }
        guard let frame = frames.first, let fill = fillRatio(of: frame) else { return identity }
        let aspect = Double(frame.width) / Double(frame.height)
        var s = targetFill / fill.heightFraction
        if fill.widthFraction > 0 {
            s = min(s, maxWidthOverHeight / (fill.widthFraction * aspect))
        }
        s = min(max(s, minScale), maxScale)
        let placement = Placement(
            scale: s,
            centerDX: 0.5 - fill.centerX,
            centerDY: 0.5 - fill.centerY,
            bottomMargin: fill.bottomMargin,
            artWidthOverHeight: fill.widthFraction * aspect / fill.heightFraction,
            visibleHeightFraction: fill.heightFraction * s
        )
        placements[id] = placement
        return placement
    }

    /// Opaque bounding box of the artwork, measured on a small downsampled
    /// copy (a full-dex scan must stay cheap). Rows scan top-down, matching
    /// SwiftUI's y axis.
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
            heightFraction: Double(maxY - minY + 1) / Double(h),
            centerX: (Double(minX) + Double(maxX) + 1) / 2 / Double(w),
            centerY: (Double(minY) + Double(maxY) + 1) / 2 / Double(h),
            bottomMargin: Double(h - 1 - maxY) / Double(h)
        )
    }

    /// Test hook.
    static func reset() {
        placements.removeAll()
    }
}
