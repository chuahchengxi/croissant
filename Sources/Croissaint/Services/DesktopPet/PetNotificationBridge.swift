// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import SQLite3
import SwiftUI

// MARK: - Pixel rendering helpers

enum PetPixelArt {
    /// Renders text as chunky pixel type: bold monospaced glyphs with a
    /// hard black outline and white fill, word-wrapped onto at most two
    /// lines. Every banner renders at the same fixed scale — a per-banner
    /// "shrink long text" rule used to make consecutive notifications look
    /// like two different fonts.
    static func text(_ raw: String) -> CGImage? {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lines = wrap(raw, into: 2, of: 34, font: font)
        guard !lines.isEmpty else { return nil }

        let lineHeight: CGFloat = 17
        let widths = lines.map { ceil(($0 as NSString).size(withAttributes: attrs).width) + 4 }
        let width = max(8, widths.max() ?? 8)
        let height = lineHeight * CGFloat(lines.count) + 4
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocusFlipped(false)
        for (index, line) in lines.enumerated() {
            let y = height - lineHeight * CGFloat(index + 1) + 2
            let point = NSPoint(x: 2, y: y)
            // Hard pixel outline: stamp black around, white on top.
            for (dx, dy) in [(1.4, 0.0), (-1.4, 0.0), (0.0, 1.4), (0.0, -1.4),
                             (1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
                (line as NSString).draw(
                    at: NSPoint(x: point.x + dx, y: point.y + dy),
                    withAttributes: attrs.merging([.foregroundColor: NSColor.black]) { _, new in new }
                )
            }
            (line as NSString).draw(
                at: point,
                withAttributes: attrs.merging([.foregroundColor: NSColor.white]) { _, new in new }
            )
        }
        image.unlockFocus()
        // Fixed 2× for every banner: one size, one font, always.
        return upscaled(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil), factor: 2
        )
    }

    /// Greedy word wrap, hard-clamped to `maxLines` lines.
    private static func wrap(_ raw: String, into maxLines: Int, of maxChars: Int, font: NSFont) -> [String] {
        let cleaned = raw.replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        var lines: [String] = []
        var current = ""
        for word in cleaned {
            let candidate = current.isEmpty ? word : current + " " + word
            if candidate.count <= maxChars {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                current = String(word.prefix(maxChars))
                if lines.count == maxLines { break }
            }
            if lines.count == maxLines { break }
        }
        if !current.isEmpty, lines.count < maxLines {
            lines.append(current)
        }
        if lines.count == maxLines, !cleaned.isEmpty {
            // Truncation marker on the last line when content spilled over.
            let rendered = lines.joined(separator: " ").count
            if rendered < cleaned.joined(separator: " ").count {
                lines[maxLines - 1] = String(lines[maxLines - 1].dropLast(1)) + "…"
            }
        }
        return lines
    }

    /// Downscales an app icon to a tiny crisp bitmap and upscales it back —
    /// the pixelated-icon look for notification banners.
    static func icon(_ source: NSImage) -> CGImage? {
        let tiny = 14
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: tiny, pixelsHigh: tiny,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
        else { return nil }
        rep.size = NSSize(width: tiny, height: tiny)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(
            in: NSRect(x: 0, y: 0, width: tiny, height: tiny),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return upscaled(rep.cgImage, factor: 2)
    }

    private static func upscaled(_ image: CGImage?, factor: Int) -> CGImage? {
        guard let image else { return nil }
        let width = image.width * factor
        let height = image.height * factor
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// Pixel type on its own, for anywhere the pet world needs text: same fixed
/// scale and outline as the notification banner, so every piece of pet copy
/// reads as one font at one size.
struct PixelTextView: View {
    let text: String

    var body: some View {
        if let image = PetPixelArt.text(text) {
            Image(decorative: image, scale: 2)
                .interpolation(.none)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Notice model + banner

struct PetNotice: Identifiable, Equatable {
    let id = UUID()
    let text: CGImage?
    let icon: CGImage?
}

struct PetNoticeBannerView: View {
    let notice: PetNotice

    /// Intrinsic size so the host panel can match it exactly.
    static func size(for notice: PetNotice) -> NSSize {
        let textWidth = CGFloat(notice.text?.width ?? 0)
        let textHeight = CGFloat(notice.text?.height ?? 0)
        let iconSide: CGFloat = notice.icon == nil ? 0 : 28
        let width = iconSide + (iconSide > 0 && textWidth > 0 ? 9 : 0) + textWidth + 22
        let height = max(iconSide, textHeight) + 14
        return NSSize(width: max(60, width), height: max(34, height))
    }

    var body: some View {
        HStack(spacing: 9) {
            if let icon = notice.icon {
                Image(decorative: icon, scale: 2)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            if let text = notice.text {
                Image(decorative: text, scale: 2)
                    .interpolation(.none)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Bridge

/// Feeds the buddy's pixel banner from two sources:
///  * in-app toasts (`.pokePalToast`) — always available;
///  * macOS notifications via the usernoted SQLite store — best effort,
///    disabled silently when the store is unreadable (it sits behind TCC, so
///    without Full Disk Access the poll simply finds nothing to open).
/// Polling runs on a utility queue every 4 s while the pet is out; the banner
/// itself costs two tiny images and one view.
final class PetNotificationBridge {
    static let shared = PetNotificationBridge()

    private weak var vm: DesktopViewModel?
    private var toastObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var queue = DispatchQueue(label: "croissaint.petNotifications", qos: .utility)
    private var db: OpaquePointer?
    private var lastSeenRowID: Int64 = -1

    private static let candidates = [
        "Group Containers/group.com.apple.usernoted/store2",
        "Group Containers/group.com.apple.usernoted/notifications.db",
    ]

    func start(vm: DesktopViewModel) {
        guard toastObserver == nil else { return }
        self.vm = vm
        toastObserver = NotificationCenter.default.addObserver(
            forName: .pokePalToast, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.userInfo?["message"] as? String else { return }
            let icon = NSApplication.shared.applicationIconImage
            self?.vm?.showNotice(text: text, icon: icon)
        }
        queue.async { [weak self] in
            self?.openStore()
            self?.readLatest()
        }
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.readLatest() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        if let toastObserver {
            NotificationCenter.default.removeObserver(toastObserver)
            self.toastObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        queue.async { [weak self] in
            if let db = self?.db {
                sqlite3_close_v2(db)
                self?.db = nil
            }
        }
        vm = nil
    }

    /// Delivers a banner; used by the toast observer and the store poller.
    /// System-store notifications startle the buddy; in-app toasts don't.
    private func deliver(text: String, icon: NSImage?, startles: Bool = false) {
        DispatchQueue.main.async {
            self.vm?.showNotice(text: text, icon: icon, startles: startles)
        }
    }

    // MARK: System store

    private func openStore() {
        guard db == nil else { return }
        let base = FileManager.default.homeDirectoryForCurrentUser
        for candidate in Self.candidates {
            let path = base.appendingPathComponent(candidate).path
            var handle: OpaquePointer?
            guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let handle
            else { sqlite3_close_v2(handle); continue }
            db = handle
            return
        }
    }

    private func readLatest() {
        guard let handle = db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            handle, "SELECT rowid, data FROM record ORDER BY rowid DESC LIMIT 6", -1, &statement, nil
        ) == SQLITE_OK, let statement else {
            // Unknown schema or unreadable store: park the watcher.
            sqlite3_finalize(statement)
            sqlite3_close_v2(handle)
            db = nil
            return
        }
        defer { sqlite3_finalize(statement) }
        var newest: (rowID: Int64, payload: PetNoticeParsing.Payload, icon: NSImage?)?
        var highest = lastSeenRowID
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            if lastSeenRowID < 0 { highest = max(highest, rowID) } // skip history on launch
            guard rowID > lastSeenRowID else { continue }
            highest = max(highest, rowID)
            guard newest == nil, // only the most recent unseen row per poll
                  let blob = sqlite3_column_blob(statement, 1)
            else { continue }
            let byteCount = Int(sqlite3_column_bytes(statement, 1))
            let data = Data(bytes: blob, count: byteCount)
            guard let payload = PetNoticeParsing.parse(data) else { continue }
            newest = (rowID, payload, resolveIcon(for: payload.bundleID))
        }
        lastSeenRowID = highest
        if let newest {
            deliver(text: newest.payload.text, icon: newest.icon, startles: true)
        }
    }

    /// The posting app's icon at banner size; nil when the bundle can't be
    /// located (web notifications without an app record, etc.).
    private func resolveIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}


// MARK: - Notice panel

/// A borderless, click-through panel that shows the pixel banner next to the
/// buddy. It lives outside the pet window so text is never capped by the
/// pet's 170 pt box — the panel sizes itself to whatever the text needs and
/// the controller clamps it into the visible screen area.
final class PetNoticePanel {
    private var panel: NSPanel?
    private weak var petWindow: NSPanel?

    init(petWindow: NSPanel?) {
        self.petWindow = petWindow
    }

    func show(notice: PetNotice) {
        let size = PetNoticeBannerView.size(for: notice)
        let root = PetNoticeBannerView(notice: notice)
            .frame(width: size.width, height: size.height)
        let content = PetPassThroughHostingView(rootView: root)
        content.frame = NSRect(origin: .zero, size: size)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = content
        } else {
            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            self.panel = panel
        }
        panel.setContentSize(size)
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func stop() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Keeps the banner glued above the buddy, flipped below near the screen
    /// top, clamped into the visible frame on both axes.
    func reposition() {
        guard let panel, let petFrame = petWindow?.frame, panel.isVisible else { return }
        let size = panel.frame.size
        let screen = petWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 6
        var origin = NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + gap)
        if origin.y + size.height > screen.maxY {
            origin.y = petFrame.minY - gap - size.height
        }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        origin.y = min(max(origin.y, screen.minY + 4), screen.maxY - size.height - 4)
        panel.setFrameOrigin(origin)
    }
}
