// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi
//
// Regenerates Resources/Brand/logo.png from logo-source.png (the flat-colour
// croissant art). The app tints the mark as a TEMPLATE image, which flattens
// every colour to one ink — so the segment seams only read if they are actual
// holes in the alpha channel. This cuts them:
//   swift Tools/CutLogoSeams.swift Resources/Brand/logo-source.png Resources/Brand/logo.png 6 18
// Args: <in> <out> [half line width px] [channel step that counts as a seam]
//
// Seams are found as hard colour STEPS between the flat bands; the smooth
// gradient inside a band stays untouched (a quantized comparison speckles it).
import AppKit

let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let d = Int(CommandLine.arguments[3]) ?? 5           // half line width, px
let threshold = Int(CommandLine.arguments[4]) ?? 26  // channel step that counts as a seam

guard let src = NSImage(contentsOfFile: inPath) else { exit(1) }
let w = Int(src.size.width), h = Int(src.size.height)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: w * 4, bitsPerPixel: 32),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
src.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()

let px = rep.bitmapData!
@inline(__always) func at(_ x: Int, _ y: Int) -> Int { (y * w + x) * 4 }
@inline(__always) func opaque(_ x: Int, _ y: Int) -> Bool { px[at(x, y) + 3] > 200 }
// Sesame seeds are near-white specks; a step onto one is not a band seam.
@inline(__always) func seed(_ x: Int, _ y: Int) -> Bool {
    let i = at(x, y)
    return px[i] > 220 && px[i + 1] > 200 && px[i + 2] > 160
}
@inline(__always) func step(_ a: Int, _ b: Int) -> Int {
    max(abs(Int(px[a]) - Int(px[b])),
        max(abs(Int(px[a + 1]) - Int(px[b + 1])), abs(Int(px[a + 2]) - Int(px[b + 2]))))
}

var cut = [Bool](repeating: false, count: w * h)
let offsets = [(d, 0), (-d, 0), (0, d), (0, -d), (d, d), (-d, -d), (d, -d), (-d, d)]
for y in d..<(h - d) {
    for x in d..<(w - d) {
        guard opaque(x, y) else { continue }
        // Skip the seeds and their antialiased halo: the step from halo to
        // crust is not a band seam, and cutting it leaves specks.
        var nearSeed = false
        let seedGuard = d * 2
        for dy in -seedGuard...seedGuard where !nearSeed {
            for dx in -seedGuard...seedGuard where seed(min(max(x + dx, 0), w - 1),
                                                        min(max(y + dy, 0), h - 1)) {
                nearSeed = true; break
            }
        }
        guard !nearSeed else { continue }
        // Keep the silhouette intact: never cut where the line would break the
        // outer contour open.
        var interior = true
        for (dx, dy) in offsets where !opaque(x + dx, y + dy) { interior = false; break }
        guard interior else { continue }
        let me = at(x, y)
        for (dx, dy) in offsets {
            let nx = x + dx, ny = y + dy
            if seed(nx, ny) { continue }
            if step(me, at(nx, ny)) >= threshold { cut[y * w + x] = true; break }
        }
    }
}

for i in 0..<(w * h) where cut[i] { px[i * 4 + 3] = 0 }
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("cut \(cut.filter { $0 }.count) px")
