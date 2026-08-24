// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

struct SpeciesDef: Identifiable {
    let key: String
    /// One name per evolution stage, e.g. Rowlet / Dartrix / Decidueye.
    let names: [String]
    let evoIDs: [Int]
    let tagline: String

    var id: String { key }
    var name: String { names[0] }
    var displayName: String { names[0] }
    var baseID: Int { evoIDs[0] }
    var supportsEvolution: Bool { evoIDs.count > 1 }
    var spriteIDs: [Int] { evoIDs }

    /// The species' name at a given evolution stage.
    func name(at stage: Int) -> String { names[min(max(0, stage), names.count - 1)] }

    static func lookup(_ key: String) -> SpeciesDef? {
        // Keys used to be hand-written base names; a save from before the full
        // catalog may point at a stage that is no longer a chain's root.
        speciesIndex[key] ?? speciesCatalog.first { def in
            def.names.contains { normalizedKey($0) == key }
        }
    }

    static func normalizedKey(_ name: String) -> String {
        name.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}

/// The whole National Dex. Every species is pickable as a buddy and carries the
/// remainder of its evolution line, so choosing Dartrix still ends at Decidueye.
let speciesCatalog: [SpeciesDef] = {
    struct Row { let name: String; let tagline: String; let next: Int? }
    var rows: [Int: Row] = [:]
    var order: [Int] = []

    for line in speciesCatalogData.split(separator: "\n") {
        let cols = line.split(separator: "|", omittingEmptySubsequences: false)
        guard cols.count == 4, let id = Int(cols[0]) else { continue }
        rows[id] = Row(name: String(cols[1]), tagline: String(cols[2]), next: Int(cols[3]))
        order.append(id)
    }

    var used = Set<String>()
    return order.compactMap { id -> SpeciesDef? in
        guard let row = rows[id] else { return nil }
        var ids = [id]
        // Three stages is all the level thresholds cover.
        while ids.count < 3, let next = rows[ids.last!]?.next, rows[next] != nil {
            ids.append(next)
        }
        // Nidoran is the only name clash once punctuation is stripped.
        var key = SpeciesDef.normalizedKey(row.name)
        if !used.insert(key).inserted { key += "\(id)" }
        return SpeciesDef(
            key: key,
            names: ids.map { rows[$0]!.name },
            evoIDs: ids,
            tagline: row.tagline
        )
    }
}()

private let speciesIndex: [String: SpeciesDef] =
    Dictionary(speciesCatalog.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
