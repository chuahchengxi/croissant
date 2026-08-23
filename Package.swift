// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "Croissaint",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Croissaint",
            path: "Sources/Croissaint"
        )
    ]
)
