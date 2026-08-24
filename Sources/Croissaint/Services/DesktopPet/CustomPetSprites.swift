// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

/// Locally drawn characters that are not part of the National Dex. Their IDs
/// live at 10000+ so they can never collide with a real dex number; instead of
/// downloading a PokeAPI sprite, SpriteCache renders these to an animated GIF
/// on disk, and everything downstream (panel, picker, wild encounters) treats
/// them like any other species.
enum CustomPetSprites {
    static let idLowerBound = 10_000

    /// Draws every idle frame of the character and writes an animated GIF to
    /// `url`. Returns false for unknown ids or if encoding fails.
    static func generate(id: Int, to url: URL) -> Bool {
        switch id {
        case 10_001: return encodeGIF(nailongFrames(), frameDelay: 0.12, to: url)
        default: return false
        }
    }

    // MARK: - Nailong

    /// Chubby sunny-yellow dragon: one round blob of a body, big duang-duang
    /// belly, oversized eyes, no ears, tongue lolling out. The idle loop is a
    /// gentle six-frame bounce with a little squash at the bottom.
    private static func nailongFrames() -> [CGImage] {
        (0..<6).compactMap { frame -> CGImage? in
            let t = CGFloat(frame) / 6 * 2 * .pi
            let rise = sin(t)
            return render(size: 128) { ctx in
                ctx.saveGState()
                ctx.translateBy(x: 64, y: 20)
                ctx.scaleBy(x: 1 + max(0, -rise) * 0.025, y: 1 - max(0, -rise) * 0.05)
                ctx.translateBy(x: -64, y: -20)
                ctx.translateBy(x: 0, y: rise * 3)
                drawNailong(in: ctx)
                ctx.restoreGState()
            }
        }
    }

    private static func drawNailong(in ctx: CGContext) {
        let yellow = rgb(255, 217, 61)
        let shade = rgb(240, 196, 42)
        let cream = rgb(255, 245, 199)
        let ink = rgb(43, 32, 18)
        let blush = rgb(255, 158, 176, alpha: 0.6)
        let mouth = rgb(122, 62, 31)
        let tongue = rgb(255, 122, 133)

        // Tail nub and stubby arms peek out from behind the body.
        fill(ctx, yellow, ellipse(94, 34, w: 18, h: 18))
        fillRotated(ctx, yellow, center: (25, 62), size: (15, 22), radians: .pi / 7)
        fillRotated(ctx, yellow, center: (103, 62), size: (15, 22), radians: -.pi / 7)

        // The whole dragon is essentially one plump egg.
        fill(ctx, yellow, ellipse(26, 20, w: 76, h: 92))
        fill(ctx, shade, ellipse(26, 20, w: 76, h: 14))
        fill(ctx, cream, ellipse(39, 24, w: 50, h: 42))

        // Feet tucked under the belly.
        fill(ctx, yellow, ellipse(41, 17, w: 20, h: 13))
        fill(ctx, yellow, ellipse(67, 17, w: 20, h: 13))

        // Blush, eyes with a glint, and the open tongue-out grin.
        fill(ctx, blush, ellipse(33, 70, w: 12, h: 9))
        fill(ctx, blush, ellipse(83, 70, w: 12, h: 9))
        fill(ctx, ink, ellipse(45, 80, w: 13, h: 17))
        fill(ctx, ink, ellipse(70, 80, w: 13, h: 17))
        fill(ctx, .white, ellipse(49, 86, w: 5, h: 5))
        fill(ctx, .white, ellipse(74, 86, w: 5, h: 5))
        fill(ctx, mouth, ellipse(49, 64, w: 30, h: 17))
        fill(ctx, tongue, ellipse(57, 57, w: 16, h: 12))
    }

    // MARK: - Drawing helpers

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
    }

    private static func ellipse(_ x: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private static func fill(_ ctx: CGContext, _ color: CGColor, _ rect: CGRect) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: rect)
    }

    private static func fillRotated(
        _ ctx: CGContext, _ color: CGColor,
        center: (x: CGFloat, y: CGFloat), size: (w: CGFloat, h: CGFloat), radians: CGFloat
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: radians)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: -size.w / 2, y: -size.h / 2, width: size.w, height: size.h))
        ctx.restoreGState()
    }

    private static func render(size: Int, _ draw: (CGContext) -> Void) -> CGImage? {
        guard
            let ctx = CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        draw(ctx)
        return ctx.makeImage()
    }

    // MARK: - GIF encoding

    private static func encodeGIF(_ frames: [CGImage], frameDelay: Double, to url: URL) -> Bool {
        guard !frames.isEmpty,
              let dest = CGImageDestinationCreateWithURL(
                  url as CFURL, "com.compuserve.gif" as CFString, frames.count, nil
              )
        else { return false }
        var firstFrame: [CFString: Any] = [kCGImagePropertyGIFDelayTime: frameDelay]
        // A loop count of 0 means forever; ImageIO reads it from frame 1.
        firstFrame[kCGImagePropertyGIFLoopCount] = 0
        let first = [kCGImagePropertyGIFDictionary: firstFrame] as CFDictionary
        let rest = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary
        for (index, frame) in frames.enumerated() {
            CGImageDestinationAddImage(dest, frame, index == 0 ? first : rest)
        }
        return CGImageDestinationFinalize(dest)
    }
}
