// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum SpriteCache {
    static let dir: URL = {
        let base = PrivateFileStore.containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base
            .appendingPathComponent("DesktopPet", isDirectory: true)
            .appendingPathComponent("sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func localURL(_ id: Int) -> URL {
        dir.appendingPathComponent("\(id).gif")
    }

    private static var frameCache: [Int: [CGImage]] = [:]

    /// All frames of the cached sprite (animated GIFs yield many; PNG fallback yields one).
    /// Returns nil while the sprite is still downloading (fetch kicked off automatically).
    ///
    /// Frames come from ImageIO rather than NSImage.representations: current
    /// AppKit collapses an animated GIF into a single representation, which
    /// silently turned every pet into a still image.
    static func frames(for id: Int) -> [CGImage]? {
        if let cached = frameCache[id] { return cached }
        let url = localURL(id)
        var cgs: [CGImage] = []
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            for index in 0..<CGImageSourceGetCount(src) {
                if let frame = CGImageSourceCreateImageAtIndex(src, index, nil) {
                    cgs.append(frame)
                }
            }
        }
        if !cgs.isEmpty {
            frameCache[id] = cgs
            return cgs
        }
        // A file that exists but cannot be parsed is worse than no file: it
        // would block every future fetch. Drop it so the refetch starts clean.
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        prefetch(ids: [id], done: nil)
        return nil
    }

    /// Drops cached frames so a re-downloaded sprite gets picked up.
    static func invalidate(_ id: Int) {
        frameCache.removeValue(forKey: id)
    }

    /// Returns cached sprite, kicking off a background fetch if missing.
    static func image(for id: Int) -> NSImage? {
        if let img = NSImage(contentsOf: localURL(id)) { return img }
        prefetch(ids: [id], done: nil)
        return nil
    }

    static func prefetch(ids: [Int], done: (() -> Void)?) {
        let group = DispatchGroup()
        var any = false
        for id in ids where !FileManager.default.fileExists(atPath: localURL(id).path) {
            any = true
            group.enter()
            fetch(id) { group.leave() }
        }
        group.notify(queue: .main) {
            if any { done?() }
        }
    }

    private static func fetch(_ id: Int, completion: @escaping () -> Void) {
        // Custom characters are drawn locally, never fetched.
        if id >= CustomPetSprites.idLowerBound {
            if CustomPetSprites.generate(id: id, to: localURL(id)) { notifyUpdated() }
            completion()
            return
        }
        let animated = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/\(id).gif"
        download(animated, to: localURL(id)) { ok in
            if ok { notifyUpdated(); completion(); return }
            // Fallback to the static front sprite.
            let pngURL = dir.appendingPathComponent("\(id).gif") // extension doesn't matter to NSImage
            let fallback = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png"
            download(fallback, to: pngURL) { ok2 in
                if ok2 { notifyUpdated() }
                completion()
            }
        }
    }

    private static func notifyUpdated() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .spriteCacheDidUpdate, object: nil)
        }
    }

    private static func download(_ urlString: String, to dest: URL, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data, NSImage(data: data) != nil else {
                completion(false); return
            }
            do {
                try data.write(to: dest, options: .atomic)
                completion(true)
            } catch {
                completion(false)
            }
        }.resume()
    }
}
