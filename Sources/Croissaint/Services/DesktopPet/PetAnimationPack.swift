// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// The per-species animation table, parsed once from the copy of
/// `pet-animation-pack.bin` that ships inside the app bundle.
///
/// This used to be an opt-in download from the release repo. At 21 KB — a
/// third of a single sprite GIF, and smaller than this file's own compiled
/// code — the download bought nothing but a settings toggle, a "not
/// installed" state whenever the fetch failed, and a nasty failure mode: a
/// pack left on disk from an older format version is rejected by the parser,
/// which silently switched every pack animation off with no way for the user
/// to tell why. Shipping it in the bundle means the table always matches the
/// binary that reads it.
///
/// Battery and performance contract: the table is a `static let`, so it is
/// parsed lazily on the first buddy frame and never re-read. Nothing polls,
/// nothing observes, and `motion(for:)` is a dictionary hit. Blinks are short
/// scheduled state flips animated by Core Animation, never a render loop.
enum PetAnimationEngine {
    /// nil only when the resource is missing or unparseable (a corrupt
    /// build). The buddy then runs the pack-free motion that shipped first,
    /// so a broken table costs animation variety and nothing else.
    static let motionTable: [Int: PetFaceMotion]? = {
        guard
            let url = Bundle.main.url(forResource: "pet-animation-pack", withExtension: "bin"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return PetAnimationPackSupport.parse(data)
    }()

    /// Animation recipe for a dex id, nil when the species has no entry.
    /// On the hot render path — keep it a dictionary hit.
    static func motion(for dexID: Int) -> PetFaceMotion? {
        motionTable?[dexID]
    }
}
