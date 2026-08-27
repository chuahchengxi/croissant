// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation

/// Pure decoder for the usernoted store's `record.data` blobs. Every app
/// that posts a user notification lands here in the same shape — a property
/// list with short keys ("app" = bundle id, "titl", "subt", "body") — but
/// apps fill the fields unevenly (some send only a body, some add a
/// subtitle, some leave blanks), so every field is optional and whitespace
/// is trimmed before anything is shown to the buddy.
enum PetNoticeParsing {
    struct Payload: Equatable {
        var text: String
        var bundleID: String?
    }

    /// Where usernoted keeps the store, relative to the home directory,
    /// newest layout first. macOS has used `db2/db` for several releases; the
    /// older names stay for earlier systems. Every one of them is behind Full
    /// Disk Access, so a wrong path here fails exactly like a missing
    /// permission — silently — which is why the prefix is pinned by a test.
    static let storeCandidates = [
        "Library/Group Containers/group.com.apple.usernoted/db2/db",
        "Library/Group Containers/group.com.apple.usernoted/store2",
        "Library/Group Containers/group.com.apple.usernoted/notifications.db",
    ]

    /// nil when the blob isn't a readable payload or carries no copy at all.
    static func parse(_ data: Data) -> Payload? {
        guard
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        else { return nil }
        let parts = [plist["titl"], plist["subt"], plist["body"]]
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return Payload(text: parts.joined(separator: " — "), bundleID: plist["app"] as? String)
    }

    /// Encodes a synthetic record blob, mirroring what usernoted stores —
    /// also the shape the tests pin against.
    static func encode(title: String?, subtitle: String?, body: String?, app: String?) -> Data? {
        var plist: [String: Any] = [:]
        if let title { plist["titl"] = title }
        if let subtitle { plist["subt"] = subtitle }
        if let body { plist["body"] = body }
        if let app { plist["app"] = app }
        return try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0
        )
    }
}
