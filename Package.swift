// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Croissaint

import PackageDescription

let package = Package(
    name: "Croissaint",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "Croissaint",
            dependencies: ["VMStatisticsCompat"],
            path: "Sources/Croissaint"
        )
    ]
)
