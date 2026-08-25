// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import CoreGraphics

/// Slices a sprite frame into a body plus two leg crops so the walking cycle
/// can swing each leg around its hip instead of waddling the whole sprite.
/// Slices are cached per (species, frame, height); the base frame with the
/// leg regions cleared is pixel-identical to the original everywhere else.
///
/// Only species the pack marked `hasLegs` are sliced — that flag means the
/// generator actually found two narrow columns standing under the body.
/// Everything else (blobs, snakes, hoverers, flyers) keeps the pack-free
/// motion rather than getting rectangles cut out of it.
enum PetSpriteSlicer {
    struct Slices {
        let body: CGImage
        let legL: CGImage
        let legR: CGImage
        /// Display-space rects (at the requested height) the crops occupy
        /// when unrotated, hip = top-centre of each.
        let legLRect: CGRect
        let legRRect: CGRect
    }

    private final class Box {
        let value: Slices
        init(_ value: Slices) { self.value = value }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    static func slices(
        id: Int, frameIndex: Int, motion: PetFaceMotion, height: CGFloat
    ) -> Slices? {
        guard motion.hasLegs, motion.canvasHeight > 0, motion.legWidth > 0,
              let frames = SpriteCache.frames(for: id),
              !frames.isEmpty
        else { return nil }
        let frame = frames[min(frameIndex, frames.count - 1)]
        let key = "\(id)#\(frameIndex)#\(Int(height))" as NSString
        if let cached = cache.object(forKey: key)?.value { return cached }

        let scale = height / CGFloat(motion.canvasHeight)
        // Geometry lives in PetAnimationPackSupport so the test harness can
        // pin it without dragging AppKit in — including the image-space to
        // context-space flip that `clearing` depends on.
        guard let legs = PetAnimationPackSupport.legSlices(
            for: motion,
            frameWidth: Double(frame.width),
            frameHeight: Double(frame.height)
        ) else { return nil }
        let rect: (PetLegSlice) -> CGRect = {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        let lRect = rect(legs.left)
        let rRect = rect(legs.right)
        guard let legL = frame.cropping(to: lRect),
              let legR = frame.cropping(to: rRect)
        else { return nil }
        let cleared = [legs.left, legs.right]

        guard let body = clearing(frame, cleared) else { return nil }

        let display: (CGRect) -> CGRect = { rect in
            CGRect(
                x: rect.minX * scale,
                y: rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }
        let slices = Slices(
            body: body, legL: legL, legR: legR,
            legLRect: display(lRect), legRRect: display(rRect)
        )
        // Cost must be passed or `totalCostLimit` above is inert and only the
        // count bounds the cache — a 271-frame sprite would then park a
        // full-canvas body copy per frame in memory.
        let cost = (body.width * body.height
                    + legL.width * legL.height
                    + legR.width * legR.height) * 4
        cache.setObject(Box(slices), forKey: key, cost: cost)
        return slices
    }

    /// Copies the frame with the given slices made transparent.
    ///
    /// Slices arrive in image space (origin top-left, matching
    /// `CGImage.cropping(to:)` and the pack's coordinates); a bitmap context
    /// draws origin-bottom-left, so every one is flipped before it is
    /// cleared. Without the flip the holes appear mirrored on the sprite's
    /// head while the real legs stay behind.
    private static func clearing(_ image: CGImage, _ slices: [PetLegSlice]) -> CGImage? {
        let width = image.width, height = image.height
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setBlendMode(.clear)
        for slice in slices {
            let flipped = slice.flippedForContext(imageHeight: Double(height))
            ctx.clear(CGRect(
                x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height
            ))
        }
        return ctx.makeImage()
    }
}
