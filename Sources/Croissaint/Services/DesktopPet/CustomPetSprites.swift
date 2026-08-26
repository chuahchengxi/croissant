// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

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

    /// Pixel-art take on the chubby golden "milk dragon": one huge egg head,
    /// green eyes with a glint, cream belly, stubby clawed arms and feet. The
    /// 40x40 map was designed against reference stills of the character and is
    /// rendered nearest-neighbour at 3px per cell onto the 128px canvas. The
    /// idle loop bounces with a squash on landing and sneaks a blink into
    /// every second cycle.
    ///
    /// No two frames of the loop are the same picture: the six beats each
    /// carry their own rise and squash, and a sheen slides across the crown
    /// over the whole twelve, so the second cycle never repeats the first.
    /// A loop that draws the same frame four times is a shorter loop wearing
    /// a longer one's delay.
    private static func nailongFrames() -> [CGImage] {
        // (rise, widthScale, heightScale) per beat; scales keep the feet planted.
        let bounce: [(rise: Int, sx: CGFloat, sy: CGFloat)] = [
            (0, 1.00, 1.00),   // rest
            (2, 0.99, 1.02),   // lift, stretching into it
            (4, 0.98, 1.03),   // apex
            (3, 0.99, 1.01),   // fall
            (1, 1.02, 0.98),   // land
            (0, 1.06, 0.93),   // squash
        ]
        var frames: [CGImage] = []
        for cycle in 0..<2 {
            for (index, beat) in bounce.enumerated() {
                let blink = cycle == 1 && index >= 4
                let sheenX = 8 + (cycle * bounce.count + index) * 2
                if let frame = renderPixelFrame(
                    map: nailongMap, blink: blink, sheenX: sheenX, beat: beat
                ) {
                    frames.append(frame)
                }
            }
        }
        return frames
    }

    /// One cell per art pixel, designed against reference stills of the
    /// character. Palette keys live in `nailongPalette`.
    private static let nailongMap: [String] = [
        "............DDDYYYYYYYYYYDDD............",
        "..........DDYYYYYYYYYYYYYYYYDD..........",
        ".........DYYYYYYYYYYYYYYYYYYYYD.........",
        "........DYYYYYYYYYYYYYYYYYYYYYYD........",
        ".......DYYYYYYYYYYYYYYYYYYYYYYYYD.......",
        "......DYYYYYYYYYYYYYYYYYYYYYYYYYYD......",
        "......DYYYYYYYYYYYYYYYYYYYYYYYYYYD......",
        ".....DYYYYYYYYYYYYYYYYYYYYYYYYYYYYD.....",
        ".....DYYYYYYYWWWWYYYYYYWWWWYYYYYYYD.....",
        ".....DYYYYYYWWWWWYYYYYYWWWWWYYYYYYD.....",
        ".....DYYYYYYWWGGGWYYYYWGGGWWYYYYYYD.....",
        ".....DYYYYYYWWKKKGYYYYWKKKGWYYYYYYD.....",
        ".....DYYYYYYWGKKKGYYYYGKKKGWYYYYYYD.....",
        ".....DYYYYYYWWGKGYYYYYYGKGWWYYYYYYD.....",
        ".....DYYYYYYYWWWYYYYYYYYWWWYYYYYYYD.....",
        "......DYYYYYYYYYYYYMMYYYYYYYYYYYYD......",
        "......DYYYYYYYYYYYMPPMYYYYYYYYYYYD......",
        ".......DYYYYYYYYYYYPPYYYYYYYYYYYD.......",
        "........DYYYYYYYYYYYYYYYYYYYYYYD........",
        ".....DDD.DYYYYYYYYYYYYYYYYYYYYD.DDD.....",
        "....DYYYD.DDYYYYYYYYYYYYYYYYDD.DYYYD....",
        "...DKYYYYDDYYYYYYYYYYYYYYYYYYDDYYYYKD...",
        "..DYYKYYYDYYYYYYYYYYYYYYYYYYYYDYYYKYYD..",
        "..DYYYYYYDYYYYYYYYCCCCYYYYYYYYDYYYYYYD..",
        "..DYYYYYYYYYYYYCCCCCCCCCCYYYYYYYYYYYYD..",
        "..DYYYYYYYYYYYCCCCCCCCCCCCYYYYYYYYYYYD..",
        "..DYYYYYYYYYYCCCCCCCCCCCCCCYYYYYYYYYYD..",
        "...DYYYDYYYYCCCCCCCCCCCCCCCCYYYYDYYYD...",
        "....DDDDYYYYCCCCCCCCCCCCCCCCYYYYDDDD....",
        "........DYYYCCCCCCCCCCCCCCCCYYYD........",
        "........DYYYCCCCCCCCCCCCCCCCYYYD........",
        ".........DYYYCCCCCCCCCCCCCCYYYD.........",
        ".........DOYYYCCCCCCCCCCCCYYYOD.........",
        "..........DOYYYCCCCCCCCCCYYYOD..........",
        "...........DYYYYYYCCCCYYYYYYD...........",
        "..........DYYYYYYYYYYYYYYYYYYD..........",
        "..........DYYYYYYYOOOOYYYYYYYD..........",
        "..........DOOYYYOODDDDOOYYYOOD..........",
        "...........DKKOODD....DDOOOKKD..........",
        "............DDDD........DDDDD...........",
    ]

    private static let nailongPalette: [Character: CGColor] = [
        "D": CGColor(srgbRed: 0.478, green: 0.290, blue: 0.071, alpha: 1),
        "Y": CGColor(srgbRed: 1.000, green: 0.851, blue: 0.361, alpha: 1),
        "O": CGColor(srgbRed: 0.941, green: 0.659, blue: 0.231, alpha: 1),
        "C": CGColor(srgbRed: 1.000, green: 0.953, blue: 0.824, alpha: 1),
        "W": CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        "G": CGColor(srgbRed: 0.290, green: 0.639, blue: 0.290, alpha: 1),
        "K": CGColor(srgbRed: 0.125, green: 0.149, blue: 0.106, alpha: 1),
        "M": CGColor(srgbRed: 0.420, green: 0.227, blue: 0.122, alpha: 1),
        "P": CGColor(srgbRed: 0.941, green: 0.502, blue: 0.549, alpha: 1),
        "B": CGColor(srgbRed: 0.980, green: 0.647, blue: 0.588, alpha: 1),
        "S": CGColor(srgbRed: 1.000, green: 0.965, blue: 0.780, alpha: 1),
    ]

    /// Paints `char` over the body cells inside a rectangle. Only plain body
    /// cells take it, so a stamp can never land on an eye, the belly or an
    /// outline.
    private static func stamp(
        _ cells: inout [String], rows: ClosedRange<Int>, columns: ClosedRange<Int>,
        with char: Character
    ) {
        for y in rows where cells.indices.contains(y) {
            var chars = Array(cells[y])
            for x in columns where chars.indices.contains(x) && chars[x] == "Y" {
                chars[x] = char
            }
            cells[y] = String(chars)
        }
    }

    /// Renders one animation frame: optionally swaps the eyes for closed
    /// lids, lays on the blush and the travelling sheen, then stamps the map
    /// bottom-centre with squash scaling and an upward offset. Cells stay
    /// axis-aligned rectangles so the pixel grid never blurs.
    private static func renderPixelFrame(
        map: [String], blink: Bool, sheenX: Int,
        beat: (rise: Int, sx: CGFloat, sy: CGFloat)
    ) -> CGImage? {
        var cells = map
        if blink {
            for (y, row) in map.enumerated() {
                var chars = Array(row)
                for x in 0..<chars.count where "WGK".contains(chars[x]) {
                    let inLeftEye = (11...18).contains(x) && (7...15).contains(y)
                    let inRightEye = (21...28).contains(x) && (7...15).contains(y)
                    if inLeftEye || inRightEye { chars[x] = "Y" }
                }
                for x in 12...18 where (11...12).contains(y) && chars[x] == "Y" { chars[x] = "O" }
                for x in 21...27 where (11...12).contains(y) && chars[x] == "Y" { chars[x] = "O" }
                cells[y] = String(chars)
            }
        }
        // Warm cheeks under the eyes, and a pale sheen sliding across the
        // crown on a slant. The sheen is what makes every frame of the loop
        // its own picture; the blush is just colour the flat gold was missing.
        stamp(&cells, rows: 15...17, columns: 8...10, with: "B")
        stamp(&cells, rows: 15...17, columns: 29...31, with: "B")
        for (offset, y) in (2...5).enumerated() {
            stamp(&cells, rows: y...y, columns: (sheenX + offset)...(sheenX + offset + 1),
                  with: "S")
        }
        let cell: CGFloat = 3
        let side = CGFloat(cells.count) * cell
        let width = side * beat.sx
        let height = side * beat.sy
        let originX = (CGFloat(canvas) - width) / 2
        let originY = CGFloat(canvas) - 4 - height - CGFloat(beat.rise)
        return render(size: canvas) { ctx in
            ctx.setShouldAntialias(false)
            for (y, row) in cells.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = nailongPalette[char] else { continue }
                    ctx.setFillColor(color)
                    ctx.fill(CGRect(
                        x: originX + CGFloat(x) * cell * beat.sx,
                        y: originY + CGFloat(cells.count - 1 - y) * cell * beat.sy,
                        width: cell * beat.sx,
                        height: cell * beat.sy
                    ))
                }
            }
        }
    }

    private static let canvas = 128

    // MARK: - Drawing helpers

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
