// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Combine
import Foundation

enum UpdateShowcaseInfo {
    static let releaseVersion = "3.1.4"
    static let mediaAssetName = "showcase.mp4"
    static let mediaSHA256 = "88031b2b48708b8eb96248fef1143432a0600382b59ad5ea39e0746af27ab9e8"

    static var localDeveloperMediaURL: URL? {
        guard AppInfo.isDeveloperBuild else { return nil }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseMediaOverride),
           let url = mediaURL(from: raw),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let desktopDemo = URL(fileURLWithPath: "/Users/croissaint/Desktop/demo.gif")
        return FileManager.default.fileExists(atPath: desktopDemo.path) ? desktopDemo : nil
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.croissaint.utils"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("UpdateShowcase", isDirectory: true)
            .appendingPathComponent(releaseVersion, isDirectory: true)
    }

    static var cachedMediaURL: URL {
        cacheDirectory.appendingPathComponent(mediaAssetName)
    }

    static func mediaIsTrusted(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return UpdateServiceSupport.sha256Matches(data, expectedHex: mediaSHA256)
    }

    static func cleanupCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private static func mediaURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return nil
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }
}

final class UpdateShowcaseMediaLoader: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(URL)
        case failed
    }

    @Published private(set) var state: State = .idle
    private var session: URLSession?

    func load() {
        if case .ready = state { return }
        if case .loading = state { return }

        if let local = UpdateShowcaseInfo.localDeveloperMediaURL {
            state = .ready(local)
            return
        }

        let cached = UpdateShowcaseInfo.cachedMediaURL
        if UpdateShowcaseInfo.mediaIsTrusted(at: cached) {
            state = .ready(cached)
            return
        }
        try? FileManager.default.removeItem(at: cached)

        // The media used to be fetched from the upstream project's releases.
        // This fork does not publish a showcase asset and does not reach into
        // anyone else's repository for one, so there is nothing to download:
        // a developer override or a warm cache plays, otherwise the step shows
        // its own "unavailable" copy and the user continues past it.
        // ponytail: the whole showcase is unreachable anyway — AppDelegate
        // gates it on AppInfo.version == "3.1.4", which this fork's 0.0.x
        // numbering can never match. Delete the feature outright (view,
        // strings, defaults keys) if it is still dead next time it is touched.
        state = .failed
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    /// `.onDisappear` is the only caller of `cancel()`, and SwiftUI can drop the
    /// `@StateObject` without it ever running. A session that is never
    /// invalidated holds its delegate for the life of the process, and the
    /// delegate's own `deinit` is what closes the scratch file and deletes it —
    /// so every exit path that leaves a scratch file behind ends here.
    /// `invalidateAndCancel()`, not `finishTasksAndInvalidate()`, which would let
    /// an abandoned download run to completion first. The completion closure
    /// captures `self` weakly and that reference is already nil by now, so the
    /// teardown cannot resurrect the loader.
    deinit {
        session?.invalidateAndCancel()
    }

    func cleanupCache() {
        UpdateShowcaseInfo.cleanupCache()
    }
}
