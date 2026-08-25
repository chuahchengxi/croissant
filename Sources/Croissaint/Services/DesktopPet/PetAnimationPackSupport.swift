// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// One detected eye, normalized to the sprite's full canvas with the y axis
/// running top-down (matching both image space and SwiftUI). Canvas-relative,
/// not bbox-relative, because the runtime lays the sprite out with
/// `scaledToFit` over the whole canvas.
struct PetEyeRect: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct PetLidColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Per-species animation recipe decoded from the animation pack. Everything
/// except `dexID` is optional in effect: a species without detected eyes
/// still carries its gait, a species without legs keeps the pack-free
/// waddle, and a species missing from the pack simply runs the pack-free
/// motion.
struct PetFaceMotion: Equatable {
    let dexID: Int
    var leftEye: PetEyeRect?
    var rightEye: PetEyeRect?
    var lidColor: PetLidColor
    /// Sprite canvas aspect (width / height); drives overlay layout to match
    /// how `scaledToFit` sizes the image.
    var widthOverHeight: Double
    /// 0 squat, 1 neutral, 2 tall — indexes into `PetAnimationPackSupport.gait`.
    var gaitClass: Int
    /// Canvas size in source pixels; leg and wing coordinates are canvas-space.
    var canvasWidth: Double
    var canvasHeight: Double
    /// Leg anchors for the sliced walking cycle: canvas-space x of each
    /// foot, the y where the leg band starts, and how wide a strip to slice.
    /// Valid when `hasLegs` — which the pack only sets for designs that
    /// actually stand on two visible legs. Blobs, snakes and hoverers keep
    /// `hasLegs == false` and fall back to the pack-free hop, because a
    /// rectangle cut out of a Gastly and swung around is worse than no
    /// animation at all.
    var hasLegs = false
    var legLX: Double = 0
    var legRX: Double = 0
    var legTopY: Double = 0
    var legWidth: Double = 0
    /// Flying species (Flying typing plus a curated few like Scyther) travel
    /// by air instead of stepping. Nothing about the sprite is sliced for
    /// them — the whole body glides, banks and flutters.
    var hasWings = false

    var hasEyes: Bool { leftEye != nil && rightEye != nil }
}

/// One sliced leg's rectangle, in image space: origin top-left, whole
/// pixels — the space the pack stores and `CGImage.cropping(to:)` reads.
struct PetLegSlice: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    /// The same rectangle in the bottom-left origin space a bitmap
    /// `CGContext` draws in. The slicer crops in image space and erases in
    /// context space; without this flip the leg-shaped holes land on the
    /// sprite's head while the real legs stay put — the single worst
    /// artefact the walk cycle ever had.
    func flippedForContext(imageHeight: Double) -> PetLegSlice {
        PetLegSlice(x: x, y: imageHeight - (y + height), width: width, height: height)
    }
}

/// Multipliers applied to the buddy's walk cycle. `.neutral` reproduces the
/// pack-free motion exactly, so a missing pack costs nothing but variety.
struct PetGait: Equatable {
    /// 0 squat, 1 neutral, 2 tall — drives pose flavour beyond the walk.
    let gaitClass: Int
    let stepRate: Double
    let bobAmplitude: Double
    let waddle: Double

    static let neutral = PetGait(gaitClass: 1, stepRate: 1, bobAmplitude: 1, waddle: 1)
}

/// Parser and motion math for `Resources/pet-animation-pack.bin`, the 21 KB
/// table produced by `Tools/gen-animation-pack.py` and shipped inside the app
/// bundle (see `PetAnimationEngine`).
///
/// Layout (little-endian): magic "CPAP", u16 version, u16 count, then 21-byte
/// records sorted by National Dex id — u16 id, u8 flags (bit 0 hasEyes,
/// bits 2-3 gait class), u8 canvas width, u8 canvas height, u8 body flags
/// (bit 0 hasLegs, bit 1 hasWings), left eye x/y/w/h, right eye x/y/w/h, lid
/// RGB, leg left-x/right-x/top-y/width — all coordinates canvas-relative.
///
/// Pure Foundation on purpose: the unit-test harness compiles this file
/// without AppKit or SwiftUI.
enum PetAnimationPackSupport {
    static let packVersion: UInt16 = 3
    /// 21 bytes per record keeps the whole 1025-species dex under 22 KB.
    static let recordSize = 21
    static let headerSize = 8
    /// Seconds the lids stay shut during one blink.
    static let blinkClosedDuration: TimeInterval = 0.13

    /// Parses pack bytes. Strict on structure: wrong magic, unknown version,
    /// truncated tail or count mismatch all yield nil so a corrupt download
    /// is never half-trusted.
    static func parse(_ data: Data) -> [Int: PetFaceMotion]? {
        guard data.count >= headerSize else { return nil }
        let bytes = [UInt8](data)
        guard
            bytes[0] == UInt8(ascii: "C"), bytes[1] == UInt8(ascii: "P"),
            bytes[2] == UInt8(ascii: "A"), bytes[3] == UInt8(ascii: "P"),
            version(bytes) == packVersion
        else { return nil }
        let declared = Int(count(bytes))
        let payload = bytes.count - headerSize
        guard payload >= 0, payload % recordSize == 0,
              declared == payload / recordSize
        else { return nil }

        var table: [Int: PetFaceMotion] = [:]
        table.reserveCapacity(declared)
        var previousID = 0
        for record in 0..<declared {
            let base = headerSize + record * recordSize
            func u8(_ offset: Int) -> Int { Int(bytes[base + offset]) }
            let dexID = u16(bytes, base)
            guard dexID > previousID else { return nil } // must stay sorted
            previousID = dexID
            let flags = u8(2)
            let canvasW = u8(3)
            let canvasH = u8(4)
            let bodyFlags = u8(5)
            let hasEyes = flags & 0b1 != 0
            let gaitClass = (flags >> 2) & 0b11

            var left: PetEyeRect?
            var right: PetEyeRect?
            if hasEyes, canvasW > 0, canvasH > 0 {
                left = rect(bytes, base, 6, canvasW, canvasH)
                right = rect(bytes, base, 10, canvasW, canvasH)
                // Degenerate rects mean the record is unusable for lids.
                if left == nil || right == nil { left = nil; right = nil }
            }
            let lid = PetLidColor(
                red: Double(u8(14)) / 255,
                green: Double(u8(15)) / 255,
                blue: Double(u8(16)) / 255
            )
            let hasLegs = bodyFlags & 0b1 != 0
            let hasWings = bodyFlags & 0b10 != 0
            table[dexID] = PetFaceMotion(
                dexID: dexID,
                leftEye: left,
                rightEye: right,
                lidColor: lid,
                widthOverHeight: canvasH > 0 ? Double(canvasW) / Double(canvasH) : 1,
                gaitClass: gaitClass > 2 ? 1 : gaitClass,
                canvasWidth: Double(canvasW),
                canvasHeight: Double(canvasH),
                hasLegs: hasLegs,
                legLX: Double(u8(17)),
                legRX: Double(u8(18)),
                legTopY: Double(u8(19)),
                legWidth: Double(u8(20)),
                hasWings: hasWings
            )
        }
        return table
    }

    /// The two leg crops for a species, clamped to the frame and snapped out
    /// to whole pixels (the crop and the rect it is drawn back into must be
    /// the same rect, or pixel art resamples and shimmers). Returns nil when
    /// the species has no sliced legs or the geometry degenerates.
    static func legSlices(
        for motion: PetFaceMotion, frameWidth: Double, frameHeight: Double
    ) -> (left: PetLegSlice, right: PetLegSlice)? {
        guard motion.hasLegs, motion.legWidth > 0, motion.canvasHeight > 0,
              frameWidth > 0, frameHeight > 0
        else { return nil }

        func slice(_ centreX: Double) -> PetLegSlice? {
            let x0 = max(0, (centreX - motion.legWidth / 2).rounded(.down))
            let x1 = min(frameWidth, (centreX + motion.legWidth / 2).rounded(.up))
            let y0 = max(0, motion.legTopY.rounded(.down))
            let y1 = min(frameHeight, motion.canvasHeight.rounded(.up))
            guard x1 > x0, y1 > y0 else { return nil }
            return PetLegSlice(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        guard let left = slice(motion.legLX), let right = slice(motion.legRX),
              left.x + left.width <= right.x    // shared column = torn seam
        else { return nil }
        return (left, right)
    }

    /// Walk-cycle multipliers for a gait class. Squat species take quicker,
    /// shallower, wobblier steps; tall ones take slower, deeper, steadier
    /// strides. Anything unknown walks neutrally.
    static func gait(forClass gaitClass: Int) -> PetGait {
        switch gaitClass {
        case 0: return PetGait(gaitClass: 0, stepRate: 1.15, bobAmplitude: 0.72, waddle: 1.4)
        case 2: return PetGait(gaitClass: 2, stepRate: 0.85, bobAmplitude: 1.22, waddle: 0.7)
        default: return .neutral
        }
    }

    /// Seconds between blinks for a species: 2.9–6.2 s, stable per dex id so
    /// the rhythm feels like a trait of that Pokemon rather than noise.
    static func blinkPeriod(for dexID: Int) -> TimeInterval {
        let seed = UInt64(bitPattern: Int64(dexID))
        let hash = UInt32(truncatingIfNeeded: seed &* 0x9E37_79B9_7F4A_7C15)
        return 2.9 + TimeInterval(hash % 321) / 100
    }

    /// Whether the lids are shut at `time` when the last blink started at
    /// `phaseStart`. Pure so tests can pin the closed window exactly.
    static func blinkIsClosed(
        phaseStart: TimeInterval, time: TimeInterval, period: TimeInterval
    ) -> Bool {
        guard period > 0 else { return false }
        let phase = (time - phaseStart).truncatingRemainder(dividingBy: period)
        let wrapped = phase < 0 ? phase + period : phase
        return wrapped < blinkClosedDuration
    }

    // MARK: - Byte decoding

    private static func version(_ bytes: [UInt8]) -> UInt16 {
        UInt16(bytes[4]) | UInt16(bytes[5]) << 8
    }

    private static func count(_ bytes: [UInt8]) -> UInt16 {
        UInt16(bytes[6]) | UInt16(bytes[7]) << 8
    }

    private static func u16(_ bytes: [UInt8], _ base: Int) -> Int {
        Int(bytes[base]) | Int(bytes[base + 1]) << 8
    }

    private static func rect(
        _ bytes: [UInt8], _ base: Int, _ offset: Int, _ bboxW: Int, _ bboxH: Int
    ) -> PetEyeRect? {
        let x = Double(bytes[base + offset])
        let y = Double(bytes[base + offset + 1])
        let w = Double(bytes[base + offset + 2])
        let h = Double(bytes[base + offset + 3])
        guard w > 0, h > 0, x + w <= Double(bboxW), y + h <= Double(bboxH) else {
            return nil
        }
        return PetEyeRect(
            x: x / Double(bboxW),
            y: y / Double(bboxH),
            width: w / Double(bboxW),
            height: h / Double(bboxH)
        )
    }
}
